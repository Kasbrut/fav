import 'package:fav/core/persistence/secure_store.dart';
import 'package:fav/features/install/data/keys/ssh_key_repository.dart';
import 'package:flutter_test/flutter_test.dart';

/// In-memory [SecureStore] backed by a plain map.
class _FakeSecureStore implements SecureStore {
  final Map<String, String> store = {};

  @override
  Future<String?> read(String key) async => store[key];

  @override
  Future<void> write(String key, String value) async {
    store[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    store.remove(key);
  }
}

void main() {
  group('SecureSshKeyRepository', () {
    test(
      'getOrCreate generates a key and persists it under a prefixed key',
      () async {
        final fake = _FakeSecureStore();
        final repo = SecureSshKeyRepository(fake);
        final keyPair = await repo.getOrCreate(
          serverId: 's1',
          comment: 'wg-prov@s1',
        );
        expect(fake.store.keys, ['ssh-key:s1']);
        expect(keyPair.seedBytes, hasLength(32));
      },
    );

    test('getOrCreate returns the same key pair on a second call', () async {
      final fake = _FakeSecureStore();
      final repo = SecureSshKeyRepository(fake);
      final first = await repo.getOrCreate(
        serverId: 's1',
        comment: 'wg-prov@s1',
      );
      final second = await repo.getOrCreate(
        serverId: 's1',
        comment: 'different-comment-ignored',
      );
      expect(second.seedBytes, first.seedBytes);
      expect(second.publicKeyBytes, first.publicKeyBytes);
    });

    test('get returns null when no key is stored', () async {
      final repo = SecureSshKeyRepository(_FakeSecureStore());
      expect(await repo.get('absent'), isNull);
    });

    test('get rehydrates the stored seed into the same public key', () async {
      final fake = _FakeSecureStore();
      final repo = SecureSshKeyRepository(fake);
      final original = await repo.getOrCreate(
        serverId: 's2',
        comment: 'wg-prov@s2',
      );
      final restored = await repo.get('s2');
      expect(restored, isNotNull);
      expect(restored!.publicKeyBytes, original.publicKeyBytes);
    });

    test('a corrupted stored seed never leaks into the error', () async {
      // Same class as audit H2 on the DB key: FormatException.toString()
      // embeds its source — here the base64 of the Ed25519 PRIVATE seed —
      // and the error propagates into rendered/logged technical detail.
      const corrupted = 'AAsWISw3Qk1YY255hI+apbC7xtHc5/L9CBMeKTQ/SlU';
      final fake = _FakeSecureStore();
      fake.store['ssh-key:s1'] = corrupted;
      final repo = SecureSshKeyRepository(fake);

      Object? thrown;
      try {
        await repo.get('s1');
      } on Object catch (error) {
        thrown = error;
      }
      expect(thrown, isNotNull);
      expect('$thrown', isNot(contains('AAsWISw3')));
    });

    test('delete removes the stored seed', () async {
      final fake = _FakeSecureStore();
      final repo = SecureSshKeyRepository(fake);
      await repo.getOrCreate(serverId: 's1', comment: 'c');
      await repo.delete('s1');
      expect(fake.store, isEmpty);
      expect(await repo.get('s1'), isNull);
    });
  });
}
