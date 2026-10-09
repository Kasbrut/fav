import 'dart:typed_data';

import 'package:fav/core/errors/app_exception.dart';
import 'package:fav/features/install/domain/ssh_client.dart';
import 'package:fav/features/peers/data/ssh/peer_script_invocation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../support/recording_ssh_client.dart';

/// Tests for the peer SSH invocation helpers. The shell-quoting here is the
/// only barrier between user-controlled peer labels / interface names and a
/// remote shell, so the adversarial cases are the point of this suite.
void main() {
  group('shellQuote', () {
    test('wraps an ordinary value in single quotes', () {
      expect(shellQuote('plain'), "'plain'");
      expect(shellQuote('with space'), "'with space'");
      expect(shellQuote(''), "''");
    });

    test('renders shell metacharacters inert (kept literal)', () {
      // Inside single quotes none of these expand or break out.
      expect(shellQuote(r'$(id)'), r"'$(id)'");
      expect(shellQuote('`id`'), "'`id`'");
      expect(shellQuote('a;b|c&d'), "'a;b|c&d'");
      expect(shellQuote(r'$HOME'), r"'$HOME'");
    });

    test('escapes an embedded single quote with the close-reopen trick', () {
      expect(shellQuote("a'b"), r"'a'\''b'");
      expect(shellQuote("'"), r"''\'''");
    });

    test('neutralizes a single-quote breakout injection attempt', () {
      // A naive `'$value'` would let this run `rm -rf ~`; the escaping keeps
      // the whole thing one literal argument.
      expect(shellQuote("'; rm -rf ~ #"), r"''\''; rm -rf ~ #'");
    });
  });

  group('stagePeerScript', () {
    test('creates a private 0700 dir and uploads the script into it', () async {
      final ssh = RecordingSshClient(
        onRun: (cmd) => const SshCommandResult(
          stdout: 'WG-PEER-STAGED\n',
          stderr: '',
          exitCode: 0,
        ),
      );
      final staged = await stagePeerScript(
        ssh: ssh,
        scriptName: 'peer_add.sh',
        bytes: Uint8List.fromList([1, 2, 3]),
        dir: '/tmp/wg-peer-fixed',
      );
      expect(staged.dir, '/tmp/wg-peer-fixed');
      expect(staged.path, '/tmp/wg-peer-fixed/peer_add.sh');
      // Stale collision cleared, then a mode-0700 dir created atomically.
      expect(ssh.runCommands.single, contains("rm -rf '/tmp/wg-peer-fixed'"));
      expect(
        ssh.runCommands.single,
        contains("mkdir -m 700 '/tmp/wg-peer-fixed'"),
      );
      expect(ssh.uploads.single.remotePath, '/tmp/wg-peer-fixed/peer_add.sh');
    });

    test('throws when the staging dir cannot be created (no marker)', () async {
      final ssh = RecordingSshClient(
        onRun: (cmd) =>
            const SshCommandResult(stdout: '', stderr: '', exitCode: 1),
      );
      await expectLater(
        stagePeerScript(
          ssh: ssh,
          scriptName: 'peer_add.sh',
          bytes: Uint8List(0),
          dir: '/tmp/wg-peer-fixed',
        ),
        throwsA(
          predicate(
            (e) => e is AppException && e.code == ErrorCode.peerApplyFailed,
          ),
        ),
      );
      expect(ssh.uploads, isEmpty);
    });
  });

  group('isSudoPasswordRejection', () {
    test('recognises the wrong-password stderr of sudo -S (F9)', () {
      expect(
        isSudoPasswordRejection(
          'Sorry, try again.\n'
          'sudo: no password was supplied\n'
          'sudo: 1 incorrect password attempt\n',
        ),
        isTrue,
      );
    });

    test('recognises the attempts-exhausted variant alone', () {
      expect(
        isSudoPasswordRejection('sudo: 3 incorrect password attempts\n'),
        isTrue,
      );
    });

    test('ignores script failures and empty output', () {
      expect(isSudoPasswordRejection('ERR-PEER-APPLY-FAILED\n'), isFalse);
      expect(isSudoPasswordRejection(''), isFalse);
    });
  });

  group('buildSudoEnvCommand', () {
    test('builds a stable, key-sorted sudo env invocation', () {
      expect(
        buildSudoEnvCommand(
          env: {'B': '2', 'A': '1'},
          remotePath: '/tmp/x.sh',
        ),
        "sudo -S -p '' -- env A='1' B='2' bash '/tmp/x.sh'",
      );
    });

    test('quotes the remote path even when it contains a single quote', () {
      expect(
        buildSudoEnvCommand(env: const {}, remotePath: "/tmp/a'b.sh"),
        r"sudo -S -p '' -- env bash '/tmp/a'\''b.sh'",
      );
    });

    test('quotes env values, defusing injection through an interface name', () {
      final command = buildSudoEnvCommand(
        env: {'WG_INTERFACE': "wg0'; rm -rf / #"},
        remotePath: '/tmp/m.sh',
      );
      expect(
        command,
        r"sudo -S -p '' -- env WG_INTERFACE='wg0'\''; rm -rf / #' bash '/tmp/m.sh'",
      );
      // The dangerous fragment never appears as an unquoted command tail.
      expect(command.endsWith("bash '/tmp/m.sh'"), isTrue);
    });
  });
}
