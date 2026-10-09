import 'package:fav/core/utils/app_logger.dart';
import 'package:fav/features/install/data/ssh/dart_ssh_client.dart';
import 'package:fav/features/install/domain/ssh_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('describeExec', () {
    const result = SshCommandResult(
      stdout: 'abcde',
      stderr: 'xy',
      exitCode: 3,
    );

    test('carries the command, exit code and output byte counts only', () {
      final line = describeExec("sudo -S -p '' -- bash '/tmp/x.sh'", result);
      expect(line, contains("sudo -S -p '' -- bash '/tmp/x.sh'"));
      expect(line, contains('exit 3'));
      expect(line, contains('stdout 5 B'));
      expect(line, contains('stderr 2 B'));
      // The output CONTENTS must never appear (client.conf carries keys).
      expect(line, isNot(contains('abcde')));
      expect(line, isNot(contains('xy')));
    });

    test('marks stdin-fed commands without ever taking the payload', () {
      // The signature takes no stdin parameter at all — the payload (sudo
      // passwords, config.env) cannot reach the log line by construction.
      final line = describeExec('cmd', result, withStdin: true);
      expect(line, contains('(with stdin)'));
    });

    test('a secret-looking command survives the redaction net', () {
      // Call sites must never put secrets in argv; if one slips through, the
      // redacting printer is the last net. Verify the line shape it relies on.
      final line = describeExec("env PASSWORD='hunter2' bash x", result);
      expect(redactSecrets(line), isNot(contains('hunter2')));
    });
  });
}
