import 'package:fav/features/peers/data/secure_peer_secret_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/in_memory_secure_store.dart';

void main() {
  group('SecurePeerSecretRepository', () {
    late InMemorySecureStore store;
    late SecurePeerSecretRepository repo;

    setUp(() {
      store = InMemorySecureStore();
      repo = SecurePeerSecretRepository(store);
    });

    test('save writes under `client_profile:<peerId>`', () async {
      await repo.save(peerId: 'p1', rawConf: '[Interface]\nPrivateKey = A=\n');
      expect(
        await store.read('client_profile:p1'),
        '[Interface]\nPrivateKey = A=\n',
      );
    });

    test('read returns the stored value', () async {
      await repo.save(peerId: 'p1', rawConf: 'conf-A');
      expect(await repo.read('p1'), 'conf-A');
    });

    test('read returns null when no entry is stored', () async {
      expect(await repo.read('missing'), isNull);
    });

    test('save overwrites an existing entry for the same peer', () async {
      await repo.save(peerId: 'p1', rawConf: 'first');
      await repo.save(peerId: 'p1', rawConf: 'second');
      expect(await repo.read('p1'), 'second');
    });

    test('delete removes the entry and is idempotent', () async {
      await repo.save(peerId: 'p1', rawConf: 'A');
      await repo.delete('p1');
      expect(await repo.read('p1'), isNull);
      await repo.delete('p1');
      expect(await repo.read('p1'), isNull);
    });
  });
}
