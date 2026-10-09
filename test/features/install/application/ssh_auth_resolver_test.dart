import 'package:fav/core/errors/app_exception.dart';
import 'package:fav/features/install/application/ssh_auth_resolver.dart';
import 'package:fav/features/install/data/keys/ssh_key_repository.dart';
import 'package:fav/features/servers/domain/server.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/in_memory_secure_store.dart';

Server _serverWithKey(String id) => Server(
  id: id,
  label: 'vps',
  host: '203.0.113.5',
  sshPort: 22,
  username: 'deploy',
  sshKeyId: id,
  createdAt: DateTime(2026, 5, 22),
);

Server _serverWithoutKey() => Server(
  id: 'srv-1',
  label: 'vps',
  host: '203.0.113.5',
  sshPort: 22,
  username: 'root',
  createdAt: DateTime(2026, 5, 22),
);

void main() {
  SshAuthResolver makeResolver(SshKeyRepository repository) =>
      SshAuthResolver(repository);

  test(
    'uses key-only auth and ignores password when a key is stored',
    () async {
      final store = InMemorySecureStore();
      final repository = SecureSshKeyRepository(store);
      // Pre-create a key under the server id so resolve() finds it.
      await repository.getOrCreate(
        serverId: 'srv-1',
        comment: 'fav@srv-1',
      );

      final params = await makeResolver(repository).resolve(
        server: _serverWithKey('srv-1'),
        password: 'should-be-ignored',
      );

      expect(params.identities, isNotNull);
      expect(params.identities, hasLength(1));
      expect(params.passwordAuthAllowed, isFalse);
      // The password field is preserved as empty — never the caller's value.
      expect(params.password, isEmpty);
    },
  );

  test(
    'throws ERR-KEY-01 when sshKeyId is set but the keystore lost the seed',
    () async {
      final repository = SecureSshKeyRepository(InMemorySecureStore());
      // Note: no getOrCreate() call — the keystore is empty.

      await expectLater(
        makeResolver(repository).resolve(server: _serverWithKey('srv-1')),
        throwsA(
          isA<AppException>().having(
            (error) => error.code,
            'code',
            ErrorCode.sshKeyUnavailable,
          ),
        ),
      );
    },
  );

  test('falls back to password auth when no key is registered', () async {
    final repository = SecureSshKeyRepository(InMemorySecureStore());

    final params = await makeResolver(repository).resolve(
      server: _serverWithoutKey(),
      password: 'secret',
    );

    expect(params.identities, isNull);
    expect(params.passwordAuthAllowed, isTrue);
    expect(params.password, 'secret');
  });

  test(
    'throws ArgumentError when no key is registered and password is missing',
    () async {
      final repository = SecureSshKeyRepository(InMemorySecureStore());

      await expectLater(
        makeResolver(repository).resolve(server: _serverWithoutKey()),
        throwsArgumentError,
      );
    },
  );

  test(
    'throws ArgumentError when no key is registered and password is empty',
    () async {
      final repository = SecureSshKeyRepository(InMemorySecureStore());

      await expectLater(
        makeResolver(repository).resolve(
          server: _serverWithoutKey(),
          password: '',
        ),
        throwsArgumentError,
      );
    },
  );
}
