import 'dart:typed_data';

import 'package:fav/core/errors/app_exception.dart';
import 'package:fav/features/install/application/anti_lockout_service.dart';
import 'package:fav/features/install/domain/management_identity.dart';
import 'package:fav/features/install/domain/run_paths.dart';
import 'package:fav/features/install/domain/ssh_client.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/recording_ssh_client.dart';
import '../../../support/server_fakes.dart';

void main() {
  const paths = RunPaths('run-lck');
  const identity = ManagementIdentity(
    username: 'deploy',
    password: 's3cret-pw',
    createdByUs: true,
  );
  final scriptBytes = Uint8List.fromList('# disable script'.codeUnits);

  Future<AntiLockoutOutcome> run(RecordingSshClient client) {
    return AntiLockoutService(() => client).disableRootSsh(
      server: testServer(),
      identity: identity,
      paths: paths,
      scriptBytes: scriptBytes,
    );
  }

  SshCommandResult ok(String stdout) =>
      SshCommandResult(stdout: stdout, stderr: '', exitCode: 0);

  test('disables root SSH when the script reports WG-LCK-OK', () async {
    final client = RecordingSshClient(
      onRun: (command) => command.contains('bash') ? ok('WG-LCK-OK\n') : ok(''),
    );
    expect(await run(client), isA<AntiLockoutDisabled>());
  });

  test('aborts when the management user cannot use sudo', () async {
    final client = RecordingSshClient(
      onRun: (command) => command.contains('-- true')
          ? const SshCommandResult(stdout: '', stderr: '', exitCode: 1)
          : ok(''),
    );
    expect(await run(client), isA<AntiLockoutAborted>());
  });

  test('aborts when the script reports WG-LCK-ABORTED', () async {
    final client = RecordingSshClient(
      onRun: (command) => command.contains('bash')
          ? const SshCommandResult(
              stdout: 'WG-LCK-ABORTED\n',
              stderr: '',
              exitCode: 1,
            )
          : ok(''),
    );
    expect(await run(client), isA<AntiLockoutAborted>());
  });

  test('aborts when connecting as the management user fails', () async {
    final client = RecordingSshClient(
      onConnect: () =>
          throw const AppException(ErrorCode.authInvalidCredentials),
    );
    final outcome = await run(client);
    expect(outcome, isA<AntiLockoutAborted>());
    expect(
      (outcome as AntiLockoutAborted).error.code,
      ErrorCode.lockoutAborted,
    );
  });

  test(
    'surfaces a host-key mismatch as ERR-HOST-01, not a login failure',
    () async {
      // A changed host key on the second session is a possible MITM and must
      // never be masked as a generic "the management user cannot log in" error.
      final client = RecordingSshClient(
        onConnect: () => throw const AppException(ErrorCode.hostKeyMismatch),
      );
      final outcome = await run(client);
      expect(outcome, isA<AntiLockoutAborted>());
      expect(
        (outcome as AntiLockoutAborted).error.code,
        ErrorCode.hostKeyMismatch,
      );
    },
  );

  test('feeds the password only through stdin, never a command', () async {
    final client = RecordingSshClient(
      onRun: (command) => command.contains('bash') ? ok('WG-LCK-OK\n') : ok(''),
    );
    await run(client);
    for (final command in client.runCommands) {
      expect(command.contains('s3cret-pw'), isFalse);
    }
    expect(
      client.runStdins.any((stdin) => stdin?.contains('s3cret-pw') ?? false),
      isTrue,
    );
  });
}
