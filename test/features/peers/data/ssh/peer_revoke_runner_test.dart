import 'dart:convert';
import 'dart:typed_data';

import 'package:fav/core/errors/app_exception.dart';
import 'package:fav/features/install/domain/ssh_client.dart';
import 'package:fav/features/peers/data/peer_script_source.dart';
import 'package:fav/features/peers/data/ssh/peer_revoke_runner.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../support/peer_script_bundle.dart';
import '../../../../support/recording_ssh_client.dart';

void main() {
  PeerRevokeRunner buildRunner() {
    return PeerRevokeRunner(
      scriptSource: PeerScriptSource(
        bundle: FakePeerAssetBundle(),
        expectedHashes: const {},
      ),
    );
  }

  /// SSH double that answers the staging command with the marker and the
  /// script invocation with [main] (chmod/rm are treated as no-ops).
  RecordingSshClient sshWith(SshCommandResult main) {
    return RecordingSshClient(
      onRun: (cmd) {
        if (cmd.contains('mkdir -m 700')) {
          return const SshCommandResult(
            stdout: 'WG-PEER-STAGED\n',
            stderr: '',
            exitCode: 0,
          );
        }
        if (cmd.startsWith('chmod') || cmd.startsWith('rm')) {
          return const SshCommandResult(stdout: '', stderr: '', exitCode: 0);
        }
        return main;
      },
    );
  }

  test(
    'uploads peer_revoke.sh, runs under sudo, returns ok on success',
    () async {
      final ssh = sshWith(
        const SshCommandResult(stdout: '', stderr: '', exitCode: 0),
      );

      final outcome = await buildRunner().run(
        ssh: ssh,
        password: 'pw',
        interfaceName: 'wg0',
        peerPublicKey: 'CLIENT-PUB',
      );

      expect(outcome, PeerRevokeOutcome.ok);
      // Staged inside a private per-invocation directory, not a fixed path.
      expect(ssh.uploads.single.remotePath, startsWith('/tmp/wg-peer-'));
      expect(ssh.uploads.single.remotePath, endsWith('/peer_revoke.sh'));
      final sudoCmd = ssh.runCommands.firstWhere((c) => c.startsWith('sudo'));
      expect(sudoCmd, contains("INTERFACE_NAME='wg0'"));
      expect(sudoCmd, contains("PEER_PUBKEY='CLIENT-PUB'"));
      expect(ssh.runStdins[ssh.runCommands.indexOf(sudoCmd)], 'pw\n');
      // Staging directory removed afterwards (last command).
      expect(ssh.runCommands.last, startsWith('rm -rf'));
    },
  );

  test('returns notFound on exit 42 + ERR-PEER-NOT-FOUND', () async {
    final ssh = sshWith(
      const SshCommandResult(
        stdout: '',
        stderr: 'ERR-PEER-NOT-FOUND\n',
        exitCode: 42,
      ),
    );
    final outcome = await buildRunner().run(
      ssh: ssh,
      password: 'pw',
      interfaceName: 'wg0',
      peerPublicKey: 'unknown',
    );
    expect(outcome, PeerRevokeOutcome.notFound);
  });

  test(
    "maps sudo's password rejection to authInvalidCredentials (F9)",
    () async {
      final ssh = sshWith(
        const SshCommandResult(
          stdout: '',
          stderr:
              'Sorry, try again.\n'
              'sudo: no password was supplied\n'
              'sudo: 1 incorrect password attempt\n',
          exitCode: 1,
        ),
      );

      await expectLater(
        buildRunner().run(
          ssh: ssh,
          password: 'pw',
          interfaceName: 'wg0',
          peerPublicKey: 'CLIENT-PUB',
        ),
        throwsA(
          predicate(
            (e) =>
                e is AppException && e.code == ErrorCode.authInvalidCredentials,
          ),
        ),
      );
    },
  );

  test(
    'stages the script in an unpredictable per-invocation path (H1)',
    () async {
      final ssh1 = sshWith(
        const SshCommandResult(stdout: '', stderr: '', exitCode: 0),
      );
      final ssh2 = sshWith(
        const SshCommandResult(stdout: '', stderr: '', exitCode: 0),
      );
      await buildRunner().run(
        ssh: ssh1,
        password: 'pw',
        interfaceName: 'wg0',
        peerPublicKey: 'CLIENT-PUB',
      );
      await buildRunner().run(
        ssh: ssh2,
        password: 'pw',
        interfaceName: 'wg0',
        peerPublicKey: 'CLIENT-PUB',
      );
      expect(
        ssh1.uploads.single.remotePath,
        isNot(ssh2.uploads.single.remotePath),
      );
      expect(ssh1.runCommands.any((c) => c.contains('mkdir -m 700')), isTrue);
    },
  );

  test('uploads override bytes into the private staging dir', () async {
    final override = Uint8List.fromList(utf8.encode('# custom revoke\n'));
    final ssh = sshWith(
      const SshCommandResult(stdout: '', stderr: '', exitCode: 0),
    );

    await buildRunner().run(
      ssh: ssh,
      password: 'pw',
      interfaceName: 'wg0',
      peerPublicKey: 'CLIENT-PUB',
      overrideBytes: override,
    );

    expect(ssh.uploads.single.data, override);
    expect(ssh.uploads.single.remotePath, startsWith('/tmp/wg-peer-'));
    expect(ssh.uploads.single.remotePath, endsWith('/peer_revoke.sh'));
  });

  test(
    'throws peerApplyFailed when the staging directory cannot be created',
    () async {
      final ssh = RecordingSshClient(
        onRun: (cmd) =>
            const SshCommandResult(stdout: '', stderr: '', exitCode: 1),
      );
      await expectLater(
        buildRunner().run(
          ssh: ssh,
          password: 'pw',
          interfaceName: 'wg0',
          peerPublicKey: 'X',
        ),
        throwsA(
          predicate(
            (e) => e is AppException && e.code == ErrorCode.peerApplyFailed,
          ),
        ),
      );
      expect(ssh.uploads, isEmpty);
    },
  );

  test('throws peerApplyFailed on an unknown non-zero exit code', () async {
    final ssh = sshWith(
      const SshCommandResult(stdout: '', stderr: '', exitCode: 9),
    );
    await expectLater(
      buildRunner().run(
        ssh: ssh,
        password: 'pw',
        interfaceName: 'wg0',
        peerPublicKey: 'X',
      ),
      throwsA(
        predicate(
          (e) => e is AppException && e.code == ErrorCode.peerApplyFailed,
        ),
      ),
    );
  });
}
