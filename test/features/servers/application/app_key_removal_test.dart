import 'package:fav/features/install/domain/ssh_client.dart';
import 'package:fav/features/servers/application/app_key_removal.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/recording_ssh_client.dart';

void main() {
  SshCommandResult ok() =>
      const SshCommandResult(stdout: '', stderr: '', exitCode: 0);

  test('removes the app key line via stdin, never on a command line', () async {
    final client = RecordingSshClient(onRun: (_) => ok());
    const line = 'ssh-ed25519 AAAAC3Nz fav@srv-1';

    await removeAppKeyFromAuthorizedKeys(client: client, publicKeyLine: line);

    for (final c in client.runCommands) {
      expect(c.contains('AAAAC3Nz'), isFalse);
    }
    expect(client.runStdins.any((s) => s == line), isTrue);
    // Edits authorized_keys (references the file in the command).
    expect(
      client.runCommands.any((c) => c.contains('authorized_keys')),
      isTrue,
    );
  });
}
