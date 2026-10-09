import 'dart:typed_data';

import 'package:fav/core/crypto/ed25519_keypair.dart';
import 'package:fav/core/errors/app_exception.dart';
import 'package:fav/features/install/application/monitoring_install_service.dart';
import 'package:fav/features/install/application/ssh_auth_resolver.dart';
import 'package:fav/features/install/data/scripts/asset_script_repository.dart';
import 'package:fav/features/install/domain/script_source.dart';
import 'package:fav/features/install/domain/ssh_client.dart';
import 'package:fav/features/servers/domain/host_key_fingerprint.dart';
import 'package:fav/features/servers/domain/server.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';

import '../../../support/fake_ssh_key_repository.dart';
import '../../../support/recording_ssh_client.dart';
import '../../../support/server_fakes.dart';

void main() {
  const okMarker = 'wg-monitor install complete';
  final silentLogger = Logger(level: Level.off);
  late SshAuthResolver resolver;

  setUpAll(() async {
    resolver = SshAuthResolver(
      FakeSshKeyRepository(await Ed25519KeyPair.generate()),
    );
  });

  // A key-authenticated server, so the resolver never requires a password.
  Server keyServer({String username = 'root'}) =>
      testServer().copyWith(username: username, sshKeyId: 'key-1');

  ScriptBundle monitorBundle({Set<String> omit = const {}}) {
    final assets = [
      for (final path in kMonitorBundleAssets)
        if (!omit.contains(path))
          ScriptAsset(
            relativePath: path,
            bytes: Uint8List.fromList('# $path\n'.codeUnits),
          ),
    ];
    return ScriptBundle(assets: assets, bundleHash: 'test-hash');
  }

  MonitoringInstallService service(RecordingSshClient client) =>
      MonitoringInstallService(
        sshClientFactory: () => client,
        authResolver: resolver,
        logger: silentLogger,
      );

  SshCommandResult ok(String stdout) =>
      SshCommandResult(stdout: stdout, stderr: '', exitCode: 0);

  // The install_monitor.sh invocation is the only `bash ...` command; the
  // chmod line mentions the script too but never `bash`.
  RecordingSshClient clientReporting(String installStdout) =>
      RecordingSshClient(
        onRun: (command) =>
            command.contains('bash') ? ok(installStdout) : ok(''),
      );

  test('falls back to the login password when no app key exists', () async {
    // A recovered run finalizes before the app key is registered on the
    // server record (M3 residual): the resolver has no key, so the service
    // must forward the transient login password — without it the whole
    // monitoring install aborted silently (live device test 2026-08-19).
    final client = clientReporting('$okMarker\n');

    final outcome = await service(client).install(
      server: testServer(),
      bundle: monitorBundle(),
      wgInterface: 'wg7',
      password: 'pw',
    );

    expect(outcome, isA<MonitoringInstallApplied>());
    expect(client.connectCount, 1);
  });

  test('aborts cleanly when neither key nor password is available', () async {
    final client = clientReporting('$okMarker\n');

    final outcome = await service(client).install(
      server: testServer(),
      bundle: monitorBundle(),
      wgInterface: 'wg7',
    );

    expect(outcome, isA<MonitoringInstallAborted>());
  });

  test('applies monitoring on a root server and cleans up staging', () async {
    final client = clientReporting('$okMarker\n');

    final outcome = await service(client).install(
      server: keyServer(),
      bundle: monitorBundle(),
      wgInterface: 'wg0',
    );

    expect(outcome, isA<MonitoringInstallApplied>());
    // All five monitor assets were uploaded.
    expect(client.uploads, hasLength(kMonitorBundleAssets.length));
    // The last command is the best-effort staging cleanup.
    expect(client.runCommands.last, contains('rm -rf'));
    expect(client.closeCount, greaterThan(0));
  });

  test(
    'elevates with sudo and never puts the password on the command line',
    () async {
      final client = clientReporting('$okMarker\n');

      final outcome = await service(client).install(
        server: keyServer(username: 'deploy'),
        bundle: monitorBundle(),
        wgInterface: 'wg0',
        sudoPassword: 'sudo-secret',
      );

      expect(outcome, isA<MonitoringInstallApplied>());
      for (final command in client.runCommands) {
        expect(command.contains('sudo-secret'), isFalse);
      }
      expect(
        client.runStdins.any(
          (stdin) => stdin?.contains('sudo-secret') ?? false,
        ),
        isTrue,
      );
    },
  );

  test(
    'aborts with ERR-AUTH-02 when a non-root install has no sudo password',
    () async {
      final client = clientReporting('$okMarker\n');

      final outcome = await service(client).install(
        server: keyServer(username: 'deploy'),
        bundle: monitorBundle(),
        wgInterface: 'wg0',
      );

      expect(outcome, isA<MonitoringInstallAborted>());
      expect(
        (outcome as MonitoringInstallAborted).error.code,
        ErrorCode.authNoSudo,
      );
    },
  );

  test(
    'aborts when install_monitor.sh does not print the success marker',
    () async {
      final client = clientReporting('partial output, no marker\n');

      final outcome = await service(client).install(
        server: keyServer(),
        bundle: monitorBundle(),
        wgInterface: 'wg0',
      );

      expect(outcome, isA<MonitoringInstallAborted>());
      expect(
        (outcome as MonitoringInstallAborted).error.code,
        ErrorCode.scriptInvalid,
      );
      // Cleanup still ran before the failure was reported.
      expect(client.runCommands.last, contains('rm -rf'));
    },
  );

  test('aborts when the bundle is missing a required monitor asset', () async {
    final client = clientReporting('$okMarker\n');

    final outcome = await service(client).install(
      server: keyServer(),
      bundle: monitorBundle(omit: {kMonitorAgentScript}),
      wgInterface: 'wg0',
    );

    expect(outcome, isA<MonitoringInstallAborted>());
    expect(
      (outcome as MonitoringInstallAborted).error.code,
      ErrorCode.scriptInvalid,
    );
  });

  test('aborts with ERR-HOST-01 on a host-key mismatch', () async {
    final client = RecordingSshClient(
      onConnect: () => throw HostKeyUnknownException(
        HostKeyFingerprint(
          host: '203.0.113.5',
          port: 22,
          keyType: 'ssh-ed25519',
          hashAlgorithm: 'md5',
          fingerprint: 'aa:bb:cc',
          pinnedAt: DateTime(2026, 5, 18),
        ),
      ),
    );

    final outcome = await service(client).install(
      server: keyServer(),
      bundle: monitorBundle(),
      wgInterface: 'wg0',
    );

    expect(outcome, isA<MonitoringInstallAborted>());
    expect(
      (outcome as MonitoringInstallAborted).error.code,
      ErrorCode.hostKeyMismatch,
    );
  });
}
