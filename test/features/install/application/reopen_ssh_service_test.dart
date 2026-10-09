import 'package:fav/features/install/application/reopen_ssh_service.dart';
import 'package:fav/features/install/domain/run_paths.dart';
import 'package:fav/features/install/domain/ssh_client.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/recording_ssh_client.dart';

void main() {
  const paths = RunPaths('run-rv');
  final scriptBytes = [0x23]; // "#"
  SshCommandResult ok(String out) =>
      SshCommandResult(stdout: out, stderr: '', exitCode: 0);

  Future<ReopenSshOutcome> run(RecordingSshClient client) {
    final service = ReopenSshService();
    return service.reopen(
      client: client,
      paths: paths,
      scriptBytes: scriptBytes,
      sudoPassword: 's3cret-pw',
    );
  }

  test('returns applied when the script reports WG-RVT-OK', () async {
    final client = RecordingSshClient(
      onRun: (c) => c.contains('bash') ? ok('WG-RVT-OK\n') : ok(''),
    );
    expect(await run(client), isA<ReopenSshApplied>());
  });

  test('returns aborted when the marker is absent', () async {
    final client = RecordingSshClient(
      onRun: (c) => c.contains('bash') ? ok('WG-RVT-ABORTED\n') : ok(''),
    );
    expect(await run(client), isA<ReopenSshAborted>());
  });

  test(
    'feeds the password via stdin, never a command, and cleans up',
    () async {
      final client = RecordingSshClient(
        onRun: (c) => c.contains('bash') ? ok('WG-RVT-OK\n') : ok(''),
      );
      await run(client);
      for (final c in client.runCommands) {
        expect(c.contains('s3cret-pw'), isFalse);
      }
      expect(
        client.runStdins.any((s) => s?.contains('s3cret-pw') ?? false),
        isTrue,
      );
      expect(client.runCommands.any((c) => c.startsWith('rm -f ')), isTrue);
    },
  );
}
