import 'package:fav/features/install/domain/management_identity.dart';
import 'package:fav/features/install/domain/new_user_spec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('resolve uses the created user for a root login', () {
    final id = ManagementIdentity.resolve(
      newUser: const NewUserSpec(username: 'deploy', password: 'pw'),
      loginUsername: 'root',
      loginPassword: 'root-pw',
    );
    expect(id.username, 'deploy');
    expect(id.password, 'pw');
    expect(id.createdByUs, isTrue);
  });

  test('resolve uses the login user when no user is created', () {
    final id = ManagementIdentity.resolve(
      newUser: null,
      loginUsername: 'lollo',
      loginPassword: 'login-pw',
    );
    expect(id.username, 'lollo');
    expect(id.password, 'login-pw');
    expect(id.createdByUs, isFalse);
  });

  test('toString redacts the password', () {
    const id = ManagementIdentity(
      username: 'lollo',
      password: 's3cret-pw',
      createdByUs: false,
    );
    expect(id.toString().contains('s3cret-pw'), isFalse);
    expect(id.toString().contains('<redacted>'), isTrue);
  });
}
