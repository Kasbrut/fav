import 'package:fav/features/install/domain/ssh_client.dart';
import 'package:fav/features/servers/domain/host_key_fingerprint.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tests for the SSH client value objects.
void main() {
  test('SshConnectionParams.toString redacts the password', () {
    const params = SshConnectionParams(
      host: '203.0.113.5',
      port: 22,
      username: 'root',
      password: 'hunter2secret',
    );
    final text = params.toString();
    expect(text, contains('203.0.113.5'));
    expect(text, contains('<redacted>'));
    expect(text, isNot(contains('hunter2secret')));
  });

  test('SshCommandResult.isSuccess reflects the exit code', () {
    const ok = SshCommandResult(stdout: 'out', stderr: '', exitCode: 0);
    const failed = SshCommandResult(stdout: '', stderr: 'err', exitCode: 1);
    expect(ok.isSuccess, isTrue);
    expect(failed.isSuccess, isFalse);
  });

  test('HostKeyUnknownException carries the unverified fingerprint', () {
    final exception = HostKeyUnknownException(
      HostKeyFingerprint(
        host: '203.0.113.5',
        port: 22,
        keyType: 'ssh-ed25519',
        hashAlgorithm: 'md5',
        fingerprint: 'aa:bb:cc',
        pinnedAt: DateTime(2026, 5, 18),
      ),
    );
    expect(exception.fingerprint.host, '203.0.113.5');
    expect(exception.toString(), contains('203.0.113.5'));
  });
}
