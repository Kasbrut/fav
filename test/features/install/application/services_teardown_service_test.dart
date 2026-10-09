import 'package:fav/features/install/application/services_teardown_service.dart';
import 'package:fav/features/install/domain/ssh_client.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/recording_ssh_client.dart';
import '../../../support/server_fakes.dart';

void main() {
  final bundle = fakeTeardownBundle();

  SshCommandResult ok([String out = '']) =>
      SshCommandResult(stdout: out, stderr: '', exitCode: 0);
  SshCommandResult fail(String err) =>
      SshCommandResult(stdout: '', stderr: err, exitCode: 1);

  // A server on which every step succeeds and prints its stdout marker: the
  // staging command echoes WG-TRD-STAGED, the orchestrator prints WG-TRD-OK.
  SshCommandResult serverOk(String c) {
    if (c.contains('teardown_wireguard.sh')) return ok('WG-TRD-OK\n');
    if (c.contains('mkdir')) return ok('WG-TRD-STAGED\n');
    return ok();
  }

  Future<ServicesTeardownOutcome> run(
    RecordingSshClient client, {
    String? sudoPassword,
  }) {
    return ServicesTeardownService().run(
      client: client,
      bundle: bundle,
      interfaceName: 'wg0',
      vpnSubnet: '10.13.13.0/24',
      sudoPassword: sudoPassword,
    );
  }

  test('returns applied when every step prints its success marker', () async {
    final client = RecordingSshClient(onRun: serverOk);
    expect(
      await run(client, sudoPassword: 'pw'),
      isA<ServicesTeardownApplied>(),
    );
  });

  test('sweeps the installer dirs after a successful teardown', () async {
    final client = RecordingSshClient(onRun: serverOk);
    await run(client, sudoPassword: 'pw');

    final sweeps = client.runCommands
        .where((c) => c.contains('/var/lib/wg-installer'))
        .toList();
    expect(
      sweeps,
      hasLength(1),
      reason: 'installer run/state/log dirs are FAV-owned residue (F3)',
    );
    expect(sweeps.single, contains('/opt/wg-installer'));
    expect(sweeps.single, contains('/var/log/wg-installer'));
    // Root-owned dirs: the sweep must be elevated for a sudoer login.
    expect(sweeps.single, contains('sudo -S'));
  });

  test(
    'can preserve installer diagnostics after a successful teardown',
    () async {
      final client = RecordingSshClient(onRun: serverOk);
      await ServicesTeardownService().run(
        client: client,
        bundle: bundle,
        interfaceName: 'wg0',
        vpnSubnet: '10.13.13.0/24',
        sudoPassword: 'pw',
        sweepInstallerDirs: false,
      );

      expect(
        client.runCommands.where(
          (c) => c.contains('/var/lib/wg-installer'),
        ),
        isEmpty,
      );
    },
  );

  test('does not sweep the installer dirs when the teardown failed', () async {
    final client = RecordingSshClient(
      onRun: (c) {
        if (c.contains('teardown_wireguard.sh')) return fail('step failed');
        if (c.contains('mkdir')) return ok('WG-TRD-STAGED\n');
        return ok();
      },
    );
    await run(client, sudoPassword: 'pw');

    expect(
      client.runCommands.where((c) => c.contains('/var/lib/wg-installer')),
      isEmpty,
      reason: 'diagnostic state files must survive a failed teardown',
    );
  });

  test(
    'treats the stdout markers as success even when the exec channel reports '
    'no exit code (-1) on OpenSSH >= 10',
    () async {
      // Regression: the no-stdin staging command and the orchestrator run can
      // come back with exitCode -1 (dartssh2 plain-exec on OpenSSH >= 10) even
      // though they succeeded. Success must key off stdout, not the exit code,
      // otherwise teardown spuriously fails with "failed to create the teardown
      // staging directory".
      final client = RecordingSshClient(
        onRun: (c) {
          if (c.contains('teardown_wireguard.sh')) {
            return const SshCommandResult(
              stdout: 'WireGuard teardown finished\nWG-TRD-OK\n',
              stderr: '',
              exitCode: -1,
            );
          }
          if (c.contains('mkdir')) {
            return const SshCommandResult(
              stdout: 'WG-TRD-STAGED\n',
              stderr: '',
              exitCode: -1,
            );
          }
          return const SshCommandResult(stdout: '', stderr: '', exitCode: -1);
        },
      );
      expect(
        await run(client, sudoPassword: 'pw'),
        isA<ServicesTeardownApplied>(),
      );
    },
  );

  test(
    'returns aborted when the orchestrator does not print WG-TRD-OK',
    () async {
      final client = RecordingSshClient(
        onRun: (c) => c.contains('teardown_wireguard.sh')
            ? fail('module failed')
            : serverOk(c),
      );
      final outcome = await run(client, sudoPassword: 'pw');
      expect(outcome, isA<ServicesTeardownAborted>());
      expect(
        (outcome as ServicesTeardownAborted).error.detail,
        'module failed',
      );
    },
  );

  test(
    'returns aborted when staging does not confirm the directory',
    () async {
      // The staging command comes back without the WG-TRD-STAGED marker.
      final client = RecordingSshClient(
        onRun: (c) => c.contains('mkdir') ? ok() : serverOk(c),
      );
      final outcome = await run(client, sudoPassword: 'pw');
      expect(outcome, isA<ServicesTeardownAborted>());
      expect(
        (outcome as ServicesTeardownAborted).error.detail,
        'failed to create the teardown staging directory',
      );
    },
  );

  test('without sudoPassword the orchestrator runs as plain bash', () async {
    final client = RecordingSshClient(onRun: serverOk);
    await run(client);
    final bashRun = client.runCommands.firstWhere(
      (c) => c.contains('teardown_wireguard.sh'),
    );
    expect(bashRun.startsWith('bash '), isTrue);
    expect(bashRun.contains('sudo'), isFalse);
  });

  test(
    'with sudoPassword the orchestrator runs via sudo -S and the password '
    'travels only via stdin',
    () async {
      final client = RecordingSshClient(onRun: serverOk);
      await run(client, sudoPassword: 's3cret-pw');

      final bashRun = client.runCommands.firstWhere(
        (c) => c.contains('teardown_wireguard.sh'),
      );
      expect(bashRun.startsWith('sudo -S -p '), isTrue);
      // The password is never on a command line.
      for (final c in client.runCommands) {
        expect(c.contains('s3cret-pw'), isFalse);
      }
      // The password is fed via stdin.
      expect(
        client.runStdins.any((s) => s?.contains('s3cret-pw') ?? false),
        isTrue,
      );
    },
  );

  test('stages in /tmp and cleans up the staging dir', () async {
    final client = RecordingSshClient(onRun: serverOk);
    await run(client, sudoPassword: 'pw');

    // The staging dir lives under /tmp, never /opt (the F3 sweep is the one
    // command that legitimately references /opt/wg-installer).
    expect(
      client.runCommands.any((c) => c.contains('/tmp/wg-trd-')),
      isTrue,
    );
    for (final c in client.runCommands.where((c) => c.contains('wg-trd-'))) {
      expect(c.contains('/opt/'), isFalse, reason: 'staging stays in /tmp');
    }
    // The staging dir is removed at the end (a standalone rm -rf).
    expect(
      client.runCommands.any(
        (c) => c.startsWith("rm -rf '/tmp/wg-trd-") && !c.contains('mkdir'),
      ),
      isTrue,
    );
  });
}
