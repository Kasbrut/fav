import 'package:fav/core/errors/app_exception.dart';
import 'package:fav/core/persistence/secure_store.dart';
import 'package:fav/features/install/data/keys/ssh_key_repository.dart';
import 'package:fav/features/install/data/ssh/dart_ssh_client.dart';
import 'package:fav/features/install/data/ssh/host_key_store.dart';
import 'package:fav/features/install/domain/ssh_client.dart';
import 'package:fav/features/peers/data/hive_peer_repository.dart';
import 'package:fav/features/peers/data/secure_peer_secret_repository.dart';
import 'package:fav/features/peers/domain/peer.dart';
import 'package:fav/features/peers/domain/peer_repository.dart';
import 'package:fav/features/profile/data/secure_client_profile_repository.dart';
import 'package:fav/features/servers/application/server_list_controller.dart';
import 'package:fav/features/servers/data/hive_server_repository.dart';
import 'package:fav/features/servers/data/server_probe.dart';
import 'package:fav/features/servers/domain/host_key_fingerprint.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/in_memory_secure_store.dart';
import '../../../support/server_fakes.dart';
import '../../../support/static_peer_repository.dart';

/// Tests for [ServerListController].
void main() {
  ProviderContainer makeContainer({
    required FakeServerRepository repository,
    Exception? connectError,
    SecureStore? secureStore,
    PeerRepository? peers,
  }) {
    final container = ProviderContainer(
      overrides: [
        serverRepositoryProvider.overrideWithValue(repository),
        secureStoreProvider.overrideWithValue(
          secureStore ?? InMemorySecureStore(),
        ),
        if (peers != null) peerRepositoryProvider.overrideWithValue(peers),
        sshClientFactoryProvider.overrideWithValue(
          () => StubSshClient(connectError: connectError),
        ),
        serverProbeProvider.overrideWithValue(
          StubServerProbe(metadata: testMetadata()),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Peer peerFor(String id, String serverId) => Peer(
    id: id,
    serverId: serverId,
    label: id,
    address: '10.13.13.2/32',
    publicKey: 'PUB-$id',
    createdAt: DateTime(2026, 5, 19),
  );

  test('build loads the servers from the repository', () async {
    final repository = FakeServerRepository();
    await repository.save(testServer(id: 'a'));
    await repository.save(testServer(id: 'b'));
    final container = makeContainer(repository: repository);

    final servers = await container.read(
      serverListControllerProvider.future,
    );

    expect(servers, hasLength(2));
  });

  test('build reattaches host-key pins from secure storage', () async {
    final repository = FakeServerRepository();
    await repository.save(testServer(id: 'a'));
    final secureStore = InMemorySecureStore();
    await HostKeyStore(secureStore).pin(
      testFingerprint(fingerprint: 'PINNED'),
    );
    final container = makeContainer(
      repository: repository,
      secureStore: secureStore,
    );

    final servers = await container.read(serverListControllerProvider.future);

    expect(servers.single.pinnedHostKey?.fingerprint, 'PINNED');
  });

  test('delete removes a server', () async {
    final repository = FakeServerRepository();
    await repository.save(testServer(id: 'a'));
    final container = makeContainer(repository: repository);
    await container.read(serverListControllerProvider.future);

    await container.read(serverListControllerProvider.notifier).delete('a');

    expect(await repository.getAll(), isEmpty);
  });

  test('reprobe refreshes the server metadata', () async {
    final repository = FakeServerRepository();
    await repository.save(testServer(id: 'a'));
    final container = makeContainer(repository: repository);
    await container.read(serverListControllerProvider.future);

    await container
        .read(serverListControllerProvider.notifier)
        .reprobe(testServer(id: 'a'), password: 'password');

    expect((await repository.getById('a'))?.metadata, isNotNull);
  });

  test('delete also evicts the saved profile and pinned host key', () async {
    // Per-server secrets (client.conf + SSH host fingerprint) must NOT
    // survive the deletion of their owning server (security review M11.M1).
    final repository = FakeServerRepository();
    final server = testServer(id: 'a');
    final host = server.host;
    final port = server.sshPort;
    await repository.save(server);
    final store = InMemorySecureStore();
    await SecureClientProfileRepository(
      store,
    ).save(serverId: 'a', rawConf: '[Interface]\n');
    await HostKeyStore(store).pin(
      HostKeyFingerprint(
        host: host,
        port: port,
        keyType: 'ssh-ed25519',
        hashAlgorithm: 'sha256',
        fingerprint: 'AAAA',
        pinnedAt: DateTime(2026, 5, 19),
      ),
    );
    final container = makeContainer(repository: repository, secureStore: store);
    await container.read(serverListControllerProvider.future);

    await container.read(serverListControllerProvider.notifier).delete('a');

    expect(await repository.getAll(), isEmpty);
    expect(
      await SecureClientProfileRepository(store).getRaw('a'),
      isNull,
    );
    expect(await HostKeyStore(store).lookup(host, port), isNull);
  });

  test('delete evicts every peer secret and the SSH key seed', () async {
    // Removing a server must not leave the peers' client.conf (private key +
    // PSK) or the app's Ed25519 seed orphaned in the OS keychain (audit H3).
    final repository = FakeServerRepository();
    await repository.save(testServer(id: 'a'));
    final store = InMemorySecureStore();
    await SecurePeerSecretRepository(
      store,
    ).save(peerId: 'p1', rawConf: '[Interface]\n1');
    await SecurePeerSecretRepository(
      store,
    ).save(peerId: 'p2', rawConf: '[Interface]\n2');
    await SecureSshKeyRepository(
      store,
    ).getOrCreate(serverId: 'a', comment: 'fav@a');
    final peers = StaticPeerRepository([
      peerFor('p1', 'a'),
      peerFor('p2', 'a'),
    ]);
    final container = makeContainer(
      repository: repository,
      secureStore: store,
      peers: peers,
    );
    await container.read(serverListControllerProvider.future);

    await container.read(serverListControllerProvider.notifier).delete('a');

    expect(await SecurePeerSecretRepository(store).read('p1'), isNull);
    expect(await SecurePeerSecretRepository(store).read('p2'), isNull);
    expect(await SecureSshKeyRepository(store).get('a'), isNull);
  });

  test(
    'delete keeps the host key when another server shares the endpoint',
    () async {
      // Two records for the same host:port (e.g. a duplicate left by a retried
      // install) share a single pinned host key. Removing one must not strip
      // the key the survivor still needs.
      final repository = FakeServerRepository();
      await repository.save(testServer(id: 'a'));
      await repository.save(testServer(id: 'b'));
      final store = InMemorySecureStore();
      await HostKeyStore(store).pin(testFingerprint());
      final container = makeContainer(
        repository: repository,
        secureStore: store,
      );
      await container.read(serverListControllerProvider.future);

      await container.read(serverListControllerProvider.notifier).delete('a');

      expect(await repository.getById('b'), isNotNull);
      expect(
        await HostKeyStore(store).lookup('203.0.113.5', 22),
        isNotNull,
      );
    },
  );

  test('reprobe rethrows a host-key confirmation request intact', () async {
    // Mapping it to ERR-HOST-01 here showed "possible MITM" for a legacy
    // MD5-era pin that merely needs re-confirmation after the SHA-256
    // migration (live device test 2026-08-19). The detail screen owns the
    // decision: it shows the re-pin dialog and pins on confirm.
    final repository = FakeServerRepository();
    await repository.save(testServer(id: 'a'));
    final fingerprint = HostKeyFingerprint(
      host: '203.0.113.5',
      port: 22,
      keyType: 'ssh-ed25519',
      hashAlgorithm: 'sha256',
      fingerprint: 'AbCdEf',
      pinnedAt: DateTime(2026, 8, 19),
    );
    final container = makeContainer(
      repository: repository,
      connectError: HostKeyUnknownException(
        fingerprint,
        previouslyTrusted: true,
      ),
    );
    await container.read(serverListControllerProvider.future);

    await expectLater(
      container
          .read(serverListControllerProvider.notifier)
          .reprobe(testServer(id: 'a'), password: 'password'),
      throwsA(
        predicate(
          (e) => e is HostKeyUnknownException && e.previouslyTrusted,
        ),
      ),
    );
  });

  test('reprobe throws when the connection fails', () async {
    final repository = FakeServerRepository();
    await repository.save(testServer(id: 'a'));
    final container = makeContainer(
      repository: repository,
      connectError: const AppException(ErrorCode.connHostUnreachable),
    );
    await container.read(serverListControllerProvider.future);

    await expectLater(
      container
          .read(serverListControllerProvider.notifier)
          .reprobe(testServer(id: 'a'), password: 'password'),
      throwsA(isA<AppException>()),
    );
  });

  test('host-key probe returns the untrusted replacement', () async {
    final repository = FakeServerRepository();
    final server = testServer(id: 'a');
    await repository.save(server);
    final replacement = testFingerprint(fingerprint: 'NEW');
    final container = makeContainer(
      repository: repository,
      connectError: HostKeyMismatchException(replacement),
    );
    await container.read(serverListControllerProvider.future);

    final received = await container
        .read(serverListControllerProvider.notifier)
        .probeHostKeyChange(server, password: 'password');

    expect(received, replacement);
  });

  test('verified host-key replacement updates pin and server record', () async {
    final repository = FakeServerRepository();
    final previous = testFingerprint(fingerprint: 'OLD');
    final replacement = testFingerprint(fingerprint: 'NEW');
    final server = testServer(id: 'a').copyWith(pinnedHostKey: previous);
    await repository.save(server);
    final secureStore = InMemorySecureStore();
    await HostKeyStore(secureStore).pin(previous);
    final container = makeContainer(
      repository: repository,
      secureStore: secureStore,
    );
    await container.read(serverListControllerProvider.future);

    await container
        .read(serverListControllerProvider.notifier)
        .replaceHostKey(server, replacement, password: 'password');

    expect(
      (await HostKeyStore(
        secureStore,
      ).lookup(server.host, server.sshPort))?.fingerprint,
      'NEW',
    );
    expect((await repository.getById('a'))?.pinnedHostKey?.fingerprint, 'NEW');
  });

  test('failed replacement authentication restores the old pin', () async {
    final repository = FakeServerRepository();
    final previous = testFingerprint(fingerprint: 'OLD');
    final replacement = testFingerprint(fingerprint: 'NEW');
    final server = testServer(id: 'a').copyWith(pinnedHostKey: previous);
    await repository.save(server);
    final secureStore = InMemorySecureStore();
    await HostKeyStore(secureStore).pin(previous);
    final container = makeContainer(
      repository: repository,
      secureStore: secureStore,
      connectError: const AppException(ErrorCode.authInvalidCredentials),
    );
    await container.read(serverListControllerProvider.future);

    await expectLater(
      container
          .read(serverListControllerProvider.notifier)
          .replaceHostKey(server, replacement, password: 'wrong'),
      throwsA(isA<AppException>()),
    );

    expect(
      (await HostKeyStore(
        secureStore,
      ).lookup(server.host, server.sshPort))?.fingerprint,
      'OLD',
    );
    expect((await repository.getById('a'))?.pinnedHostKey?.fingerprint, 'OLD');
  });
}
