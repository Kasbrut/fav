import 'package:fav/features/shell/application/pending_shell_password.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('take returns the staged password exactly once', () {
    final holder = PendingShellPasswords()..put('srv-1', 'pw');
    expect(holder.take('srv-1'), 'pw');
    // One-shot: the password must not linger in the holder.
    expect(holder.take('srv-1'), isNull);
  });

  test('take returns null for a server with nothing staged', () {
    expect(PendingShellPasswords().take('srv-1'), isNull);
  });

  test('passwords are keyed per server', () {
    final holder = PendingShellPasswords()
      ..put('srv-1', 'pw1')
      ..put('srv-2', 'pw2');
    expect(holder.take('srv-2'), 'pw2');
    expect(holder.take('srv-1'), 'pw1');
  });
}
