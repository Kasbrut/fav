import 'dart:io';

import 'package:fav/core/persistence/app_database.dart';
import 'package:fav/features/peers/data/hive_peer_repository.dart';
import 'package:fav/features/peers/domain/peer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';

import '../../../support/in_memory_secure_store.dart';

void main() {
  late Directory tempDir;
  late HivePeerRepository repo;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('wg_peers_test');
    Hive.init(tempDir.path);
    final box = await openPeersBox(InMemorySecureStore());
    repo = HivePeerRepository(box);
  });

  tearDown(() async {
    await Hive.close();
    tempDir.deleteSync(recursive: true);
  });

  Peer makePeer({
    required String id,
    required String serverId,
    String label = 'phone',
    String address = '10.13.13.3/32',
    String publicKey = 'AAA=',
    DateTime? createdAt,
  }) {
    return Peer(
      id: id,
      serverId: serverId,
      label: label,
      address: address,
      publicKey: publicKey,
      createdAt: createdAt ?? DateTime.utc(2026, 5, 26, 12),
    );
  }

  test('save then getById returns the same peer', () async {
    final peer = makePeer(id: 'p1', serverId: 's1');
    await repo.save(peer);
    final loaded = await repo.getById('p1');
    expect(loaded, peer);
  });

  test('getById returns null when no entry exists', () async {
    expect(await repo.getById('missing'), isNull);
  });

  test('save overwrites an existing entry with the same id', () async {
    await repo.save(makePeer(id: 'p1', serverId: 's1'));
    await repo.save(makePeer(id: 'p1', serverId: 's1', label: 'laptop'));
    final loaded = await repo.getById('p1');
    expect(loaded?.label, 'laptop');
  });

  test('getByServerId returns peers sorted by createdAt ascending', () async {
    await repo.save(
      makePeer(
        id: 'p2',
        serverId: 's1',
        label: 'second',
        createdAt: DateTime.utc(2026, 5, 26, 13),
      ),
    );
    await repo.save(
      makePeer(
        id: 'p1',
        serverId: 's1',
        label: 'first',
        createdAt: DateTime.utc(2026, 5, 26, 11),
      ),
    );
    await repo.save(
      makePeer(
        id: 'p3',
        serverId: 's2',
        label: 'other',
        createdAt: DateTime.utc(2026, 5, 26, 12),
      ),
    );
    final s1Peers = await repo.getByServerId('s1');
    expect(s1Peers.map((p) => p.label).toList(), ['first', 'second']);
    final s2Peers = await repo.getByServerId('s2');
    expect(s2Peers.map((p) => p.label).toList(), ['other']);
  });

  test('getAll returns every peer, sorted by createdAt ascending', () async {
    await repo.save(
      makePeer(
        id: 'p2',
        serverId: 's2',
        createdAt: DateTime.utc(2026, 5, 26, 14),
      ),
    );
    await repo.save(
      makePeer(
        id: 'p1',
        serverId: 's1',
        createdAt: DateTime.utc(2026, 5, 26, 10),
      ),
    );
    final all = await repo.getAll();
    expect(all.map((p) => p.id).toList(), ['p1', 'p2']);
  });

  test('delete removes the entry and is idempotent', () async {
    await repo.save(makePeer(id: 'p1', serverId: 's1'));
    await repo.delete('p1');
    expect(await repo.getById('p1'), isNull);
    // Second delete is a no-op.
    await repo.delete('p1');
    expect(await repo.getById('p1'), isNull);
  });
}
