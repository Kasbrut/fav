import 'dart:typed_data';

import 'package:fav/core/crypto/ed25519_keypair.dart';
import 'package:fav/core/errors/app_exception.dart';
import 'package:fav/features/install/application/hardening_service.dart';
import 'package:fav/features/install/domain/management_identity.dart';
import 'package:fav/features/install/domain/run_paths.dart';
import 'package:fav/features/install/domain/ssh_client.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/recording_ssh_client.dart';
import '../../../support/server_fakes.dart';

void main() {
  const paths = RunPaths('run-hrd');
  const identity = ManagementIdentity(
    username: 'deploy',
    password: 's3cret-pw',
    createdByUs: true,
  );
  final scriptBytes = Uint8List.fromList('# disable script'.codeUnits);

  late Ed25519KeyPair keyPair;
  setUpAll(() async {
    keyPair = await Ed25519KeyPair.generate();
  });

  Future<HardeningOutcome> run(RecordingSshClient client) {
    return HardeningService(() => client).apply(
      server: testServer(),
      identity: identity,
      keyPair: keyPair,
      paths: paths,
      scriptBytes: scriptBytes,
    );
  }

  SshCommandResult ok(String stdout) =>
      SshCommandResult(stdout: stdout, stderr: '', exitCode: 0);

  test('disables password auth when the script reports WG-HRD-OK', () async {
    final client = RecordingSshClient(
      onRun: (command) => command.contains('bash') ? ok('WG-HRD-OK\n') : ok(''),
    );
    expect(await run(client), isA<HardeningApplied>());
  });

  test(
    'aborts when the management user cannot use sudo over the key session',
    () async {
      final client = RecordingSshClient(
        onRun: (command) => command.contains('-- true')
            ? const SshCommandResult(stdout: '', stderr: '', exitCode: 1)
            : ok(''),
      );
      expect(await run(client), isA<HardeningAborted>());
    },
  );

  test('aborts when the script reports WG-HRD-ABORTED', () async {
    final client = RecordingSshClient(
      onRun: (command) => command.contains('bash')
          ? const SshCommandResult(
              stdout: 'WG-HRD-ABORTED\n',
              stderr: '',
              exitCode: 1,
            )
          : ok(''),
    );
    expect(await run(client), isA<HardeningAborted>());
  });

  test('aborts when key-based login cannot be verified', () async {
    final client = RecordingSshClient(
      onConnect: () =>
          throw const AppException(ErrorCode.authInvalidCredentials),
    );
    final outcome = await run(client);
    expect(outcome, isA<HardeningAborted>());
    expect(
      (outcome as HardeningAborted).error.code,
      ErrorCode.lockoutAborted,
    );
  });

  test(
    'feeds the password only through stdin, never as a command argument',
    () async {
      final client = RecordingSshClient(
        onRun: (command) =>
            command.contains('bash') ? ok('WG-HRD-OK\n') : ok(''),
      );
      await run(client);
      for (final command in client.runCommands) {
        expect(command.contains('s3cret-pw'), isFalse);
      }
      expect(
        client.runStdins.any((stdin) => stdin?.contains('s3cret-pw') ?? false),
        isTrue,
      );
    },
  );

  test('cleans up the remote script after the run', () async {
    final client = RecordingSshClient(
      onRun: (command) => command.contains('bash') ? ok('WG-HRD-OK\n') : ok(''),
    );
    await run(client);
    expect(
      client.runCommands.any((command) => command.startsWith('rm -f ')),
      isTrue,
    );
  });
}
