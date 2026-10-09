import 'dart:convert';
import 'dart:typed_data';

import 'package:fav/core/errors/app_exception.dart';
import 'package:fav/features/install/data/provisioner/debian_provisioner.dart';
import 'package:fav/features/install/domain/advanced_options.dart';
import 'package:fav/features/install/domain/new_user_spec.dart';
import 'package:fav/features/install/domain/run_paths.dart';
import 'package:fav/features/install/domain/script_source.dart';
import 'package:fav/features/install/domain/ssh_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';

import '../../../../support/recording_ssh_client.dart';

class _CapturingOutput extends LogOutput {
  _CapturingOutput(this.lines);
  final List<String> lines;

  @override
  void output(OutputEvent event) {
    lines.addAll(event.lines);
  }
}

void main() {
  const paths = RunPaths('run-xyz');
  final logger = Logger(level: Level.off);

  // Records commands like the default, but answers the config.env mode probe
  // (`stat -c '%a'`) with "600" so _uploadConfig's verification passes.
  RecordingSshClient configAwareClient() => RecordingSshClient(
    onRun: (command) => command.contains("stat -c '%a'")
        ? const SshCommandResult(stdout: '600\n', stderr: '', exitCode: 0)
        : const SshCommandResult(stdout: '', stderr: '', exitCode: 0),
  );

  ScriptBundle testBundle() {
    ScriptAsset asset(String path, String body) => ScriptAsset(
      relativePath: path,
      bytes: Uint8List.fromList(utf8.encode(body)),
    );
    return ScriptBundle(
      assets: [
        asset('install_wireguard.sh', '# orchestrator'),
        asset('lib/common.sh', '# common'),
        asset('modules/00_probe.sh', '# probe'),
      ],
      bundleHash: 'test-bundle-hash',
    );
  }

  test('uploads the scripts and config, then launches detached', () async {
    final client = configAwareClient();
    final provisioner = DebianProvisioner(
      client: client,
      paths: paths,
      bundle: testBundle(),
      logger: logger,
    );

    await provisioner.start(
      options: const AdvancedOptions(),
      installationId: 'install-1',
      operationId: 'operation-1',
      ipv6UlaSubnet: 'fd12:3456:789a::/64',
    );

    expect(
      client.uploads.map((upload) => upload.remotePath),
      containsAll(<String>[
        paths.scriptPath,
        paths.commonLibPath,
        paths.modulePath('00_probe.sh'),
        paths.configPath,
      ]),
    );
    final config = client.uploads.firstWhere(
      (upload) => upload.remotePath == paths.configPath,
    );
    expect(utf8.decode(config.data), contains('FAV_CONFIG_VERSION="2"'));
    expect(
      client.runCommands.any(
        (command) =>
            command.contains('mkdir -p') && command.contains('chmod 700'),
      ),
      isTrue,
    );
    expect(
      client.runCommands.any(
        (command) => command.contains("chmod 600 '${paths.configPath}'"),
      ),
      isTrue,
    );
    expect(
      client.runCommands.any(
        (command) =>
            command.contains('nohup setsid bash') &&
            command.contains(paths.pidPath),
      ),
      isTrue,
    );
  });

  test(
    'elevates run-dir creation and launch with sudo for a non-root login',
    () async {
      final client = configAwareClient();
      final provisioner = DebianProvisioner(
        client: client,
        paths: paths,
        bundle: testBundle(),
        logger: logger,
      );

      await provisioner.start(
        options: const AdvancedOptions(),
        installationId: 'install-1',
        operationId: 'operation-1',
        ipv6UlaSubnet: 'fd12:3456:789a::/64',
        sudoPassword: 's3cret-sudo',
        loginUser: 'deploy',
      );

      // mkdir runs under sudo and chowns the run dir to the login user so the
      // (non-sudo) uploads can write into it.
      expect(
        client.runCommands.any(
          (c) =>
              c.contains('sudo -S') &&
              c.contains('mkdir -p') &&
              c.contains('chown') &&
              c.contains('deploy'),
        ),
        isTrue,
      );
      // The detached launch runs under sudo too.
      expect(
        client.runCommands.any(
          (c) => c.contains('sudo -S') && c.contains('nohup setsid bash'),
        ),
        isTrue,
      );
      // The sudo password travels only via stdin.
      for (final c in client.runCommands) {
        expect(c.contains('s3cret-sudo'), isFalse);
      }
      expect(
        client.runStdins.any((s) => s?.contains('s3cret-sudo') ?? false),
        isTrue,
      );
    },
  );

  test('keeps the password out of every command', () async {
    final client = configAwareClient();
    final provisioner = DebianProvisioner(
      client: client,
      paths: paths,
      bundle: testBundle(),
      logger: logger,
    );

    await provisioner.start(
      options: const AdvancedOptions(),
      installationId: 'install-1',
      operationId: 'operation-1',
      ipv6UlaSubnet: 'fd12:3456:789a::/64',
      newUser: const NewUserSpec(username: 'deploy', password: 's3cr3t-pw'),
    );

    for (final command in client.runCommands) {
      expect(command.contains('s3cr3t-pw'), isFalse);
    }
    // The password reaches the server only inside the SFTP-uploaded
    // config.env, never as a process argument.
    final config = client.uploads.firstWhere(
      (upload) => upload.remotePath == paths.configPath,
    );
    expect(utf8.decode(config.data).contains('s3cr3t-pw'), isTrue);
  });

  test('uploads exactly the (effective) bundle bytes it is given', () async {
    // The caller passes an *effective* bundle (overrides already substituted
    // by EffectiveScriptResolver); the provisioner uploads it verbatim.
    final client = configAwareClient();
    final customBytes = Uint8List.fromList(
      utf8.encode('#!/bin/bash\n# customized orchestrator\n'),
    );
    final bundle = ScriptBundle(
      assets: [
        ScriptAsset(relativePath: 'install_wireguard.sh', bytes: customBytes),
        ScriptAsset(
          relativePath: 'lib/common.sh',
          bytes: Uint8List.fromList(utf8.encode('# common')),
        ),
      ],
      bundleHash: 'effective-hash',
    );
    final provisioner = DebianProvisioner(
      client: client,
      paths: paths,
      bundle: bundle,
      logger: logger,
    );

    await provisioner.start(
      options: const AdvancedOptions(),
      installationId: 'install-1',
      operationId: 'operation-1',
      ipv6UlaSubnet: 'fd12:3456:789a::/64',
    );

    final orchestratorUpload = client.uploads.firstWhere(
      (upload) => upload.remotePath == paths.scriptPath,
    );
    expect(orchestratorUpload.data, customBytes);
    final commonUpload = client.uploads.firstWhere(
      (upload) => upload.remotePath == paths.commonLibPath,
    );
    expect(utf8.decode(commonUpload.data), '# common');
  });

  test('never writes any script body to the logger', () async {
    // Defense-in-depth — an overridden script may contain anything; ensure no
    // logger statement embeds its body (M10-T5 security review, L2).
    final captured = <String>[];
    final captureLogger = Logger(
      level: Level.trace,
      output: _CapturingOutput(captured),
      printer: SimplePrinter(colors: false),
    );
    final client = configAwareClient();
    const canary = 'CUSTOMIZED_SCRIPT_CANARY_TOKEN';
    final bundle = ScriptBundle(
      assets: [
        ScriptAsset(
          relativePath: 'install_wireguard.sh',
          bytes: Uint8List.fromList(
            utf8.encode('#!/bin/bash\n# $canary\nexit 0\n'),
          ),
        ),
      ],
      bundleHash: 'effective-hash',
    );
    final provisioner = DebianProvisioner(
      client: client,
      paths: paths,
      bundle: bundle,
      logger: captureLogger,
    );

    await provisioner.start(
      options: const AdvancedOptions(),
      installationId: 'install-1',
      operationId: 'operation-1',
      ipv6UlaSubnet: 'fd12:3456:789a::/64',
      newUser: const NewUserSpec(username: 'deploy', password: 'pw'),
    );

    expect(captured, isNotEmpty); // sanity: logger ran at this level
    expect(captured.join('\n'), isNot(contains(canary)));
  });

  test('throws AppException when a remote command fails', () async {
    final client = RecordingSshClient(
      onRun: (command) => command.contains('mkdir')
          ? const SshCommandResult(stdout: '', stderr: '', exitCode: 1)
          : const SshCommandResult(stdout: '', stderr: '', exitCode: 0),
    );
    final provisioner = DebianProvisioner(
      client: client,
      paths: paths,
      bundle: testBundle(),
      logger: logger,
    );

    await expectLater(
      provisioner.start(
        options: const AdvancedOptions(),
        installationId: 'install-1',
        operationId: 'operation-1',
        ipv6UlaSubnet: 'fd12:3456:789a::/64',
      ),
      throwsA(isA<AppException>()),
    );
  });
  test(
    'cleanup failure does not replace the original provisioning error',
    () async {
      final client = RecordingSshClient(
        onRun: (command) {
          if (command.startsWith('rm ')) throw StateError('connection lost');
          return const SshCommandResult(stdout: '', stderr: '', exitCode: 1);
        },
      );
      final provisioner = DebianProvisioner(
        client: client,
        paths: paths,
        bundle: testBundle(),
        logger: logger,
      );
      await expectLater(
        provisioner.start(
          options: const AdvancedOptions(),
          installationId: 'install-1',
          operationId: 'operation-1',
          ipv6UlaSubnet: 'fd12:3456:789a::/64',
        ),
        throwsA(
          isA<AppException>().having(
            (e) => e.code,
            'code',
            ErrorCode.authNoSudo,
          ),
        ),
      );
    },
  );

  test('lost launch reply preserves remote files for recovery', () async {
    final client = RecordingSshClient(
      onRun: (command) {
        if (command.contains("stat -c '%a'")) {
          return const SshCommandResult(
            stdout: '600\n',
            stderr: '',
            exitCode: 0,
          );
        }
        if (command.contains('nohup setsid')) {
          throw StateError('connection reset');
        }
        return const SshCommandResult(stdout: '', stderr: '', exitCode: 0);
      },
    );
    final provisioner = DebianProvisioner(
      client: client,
      paths: paths,
      bundle: testBundle(),
      logger: logger,
    );

    await expectLater(
      provisioner.start(
        options: const AdvancedOptions(),
        installationId: 'install-1',
        operationId: 'operation-1',
        ipv6UlaSubnet: 'fd12:3456:789a::/64',
      ),
      throwsA(isA<ProvisioningLaunchUncertain>()),
    );
    expect(
      client.runCommands.where((command) => command.startsWith('rm ')),
      isEmpty,
    );
  });
}
