import 'package:fav/features/peers/data/legacy_peer_migrator.dart';
import 'package:fav/features/peers/domain/peer.dart';
import 'package:fav/features/peers/domain/peer_repository.dart';
import 'package:fav/features/peers/domain/peer_secret_repository.dart';
import 'package:fav/features/servers/domain/server.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

import '../../../support/in_memory_secure_store.dart';
import '../../../support/server_fakes.dart';

class _InMemoryPeerRepository implements PeerRepository {
  final Map<String, Peer> _peers = {};

  @override
  Future<List<Peer>> getAll() async => _peers.values.toList();

  @override
  Future<Peer?> getById(String id) async => _peers[id];

  @override
  Future<List<Peer>> getByServerId(String serverId) async =>
      _peers.values.where((p) => p.serverId == serverId).toList();

  @override
  Future<void> save(Peer peer) async {
    _peers[peer.id] = peer;
  }

  @override
  Future<void> delete(String id) async {
    _peers.remove(id);
  }
}

class _InMemoryPeerSecretRepository implements PeerSecretRepository {
  final Map<String, String> _entries = {};

  @override
  Future<void> save({required String peerId, required String rawConf}) async {
    _entries[peerId] = rawConf;
  }

  @override
  Future<String?> read(String peerId) async => _entries[peerId];

  @override
  Future<void> delete(String peerId) async {
    _entries.remove(peerId);
  }
}

Server buildServer(String id, {String label = 's'}) {
  return Server(
    id: id,
    label: label,
    host: '192.168.1.1',
    sshPort: 22,
    username: 'root',
    createdAt: DateTime.utc(2026, 5, 26),
  );
}

const legacyConf = '''
[Interface]
PrivateKey = AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=
Address = 10.13.13.2/32
DNS = 1.1.1.1, 1.0.0.1
MTU = 1420

[Peer]
PublicKey = AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=
PresharedKey = BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=
Endpoint = vpn.example.org:51820
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
''';

void main() {
  late FakeServerRepository servers;
  late _InMemoryPeerRepository peers;
  late _InMemoryPeerSecretRepository secrets;
  late InMemorySecureStore store;
  late LegacyPeerMigrator migrator;

  setUp(() {
    servers = FakeServerRepository();
    peers = _InMemoryPeerRepository();
    secrets = _InMemoryPeerSecretRepository();
    store = InMemorySecureStore();
    migrator = LegacyPeerMigrator(
      serverRepository: servers,
      peerRepository: peers,
      peerSecretRepository: secrets,
      secureStore: store,
      uuid: const Uuid(),
      clock: () => DateTime.utc(2026, 5, 26, 12),
    );
  });

  test('migrates a single legacy entry into the peers box', () async {
    await servers.save(buildServer('srv-1'));
    await store.write('client_profile:srv-1', legacyConf);

    final created = await migrator.migrate(firstClientLabel: 'First client');

    expect(created, 1);
    final migrated = await peers.getByServerId('srv-1');
    expect(migrated, hasLength(1));
    expect(migrated.single.serverId, 'srv-1');
    expect(migrated.single.label, 'First client');
    expect(migrated.single.address, '10.13.13.2/32');
    expect(migrated.single.publicKey, isNotEmpty);

    // Raw conf re-keyed under client_profile:<peerId>.
    expect(await secrets.read(migrated.single.id), legacyConf);
    // Legacy entry removed from secure storage.
    expect(await store.read('client_profile:srv-1'), isNull);
  });

  test('is idempotent on re-run', () async {
    await servers.save(buildServer('srv-1'));
    await store.write('client_profile:srv-1', legacyConf);

    final first = await migrator.migrate(firstClientLabel: 'First client');
    final second = await migrator.migrate(firstClientLabel: 'First client');
    expect(first, 1);
    expect(second, 0);
    expect(await peers.getByServerId('srv-1'), hasLength(1));
  });

  test('removes a stale legacy entry when a peer row already exists', () async {
    // Audit M-1: if a previous migration created the peer row but failed
    // to delete the legacy keystore entry, the next run must catch up and
    // retire the orphan so secrets do not live in two places.
    await servers.save(buildServer('srv-1'));
    await store.write('client_profile:srv-1', legacyConf);
    await peers.save(
      Peer(
        id: 'existing',
        serverId: 'srv-1',
        label: 'phone',
        address: '10.13.13.3/32',
        publicKey: 'X',
        createdAt: DateTime.utc(2026, 5, 26),
      ),
    );
    final created = await migrator.migrate(firstClientLabel: 'First client');
    expect(created, 0);
    // No new peer is added; the stale legacy entry is removed.
    expect(await peers.getByServerId('srv-1'), hasLength(1));
    expect(await store.read('client_profile:srv-1'), isNull);
  });

  test('does nothing when the legacy entry is missing', () async {
    await servers.save(buildServer('srv-1'));
    final created = await migrator.migrate(firstClientLabel: 'First client');
    expect(created, 0);
    expect(await peers.getByServerId('srv-1'), isEmpty);
  });

  test(
    'skips a server with a corrupt legacy entry, migrates the others',
    () async {
      await servers.save(buildServer('srv-corrupt'));
      await servers.save(buildServer('srv-ok'));
      await store.write('client_profile:srv-corrupt', 'not a conf at all');
      await store.write('client_profile:srv-ok', legacyConf);

      final created = await migrator.migrate(firstClientLabel: 'First client');
      expect(created, 1);
      expect(await peers.getByServerId('srv-corrupt'), isEmpty);
      expect(await peers.getByServerId('srv-ok'), hasLength(1));
      // The corrupt legacy entry is left in place for a future debug session.
      expect(
        await store.read('client_profile:srv-corrupt'),
        'not a conf at all',
      );
    },
  );
}
