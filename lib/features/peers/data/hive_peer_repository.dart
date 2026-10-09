import 'package:fav/core/persistence/app_database.dart';
import 'package:fav/features/peers/data/peer_mappers.dart';
import 'package:fav/features/peers/domain/peer.dart';
import 'package:fav/features/peers/domain/peer_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive_ce.dart';

/// [PeerRepository] backed by the encrypted `peers` Hive box.
class HivePeerRepository implements PeerRepository {
  /// Creates a [HivePeerRepository] over [_box].
  HivePeerRepository(this._box);

  final Box<Map<dynamic, dynamic>> _box;

  List<Peer> _sortedByCreatedAt(Iterable<Peer> peers) {
    final list = peers.toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return list;
  }

  @override
  Future<List<Peer>> getAll() async {
    return _sortedByCreatedAt(_box.values.map(peerFromMap));
  }

  @override
  Future<Peer?> getById(String id) async {
    final raw = _box.get(id);
    return raw == null ? null : peerFromMap(raw);
  }

  @override
  Future<List<Peer>> getByServerId(String serverId) async {
    return _sortedByCreatedAt(
      _box.values.map(peerFromMap).where((p) => p.serverId == serverId),
    );
  }

  @override
  Future<void> save(Peer peer) => _box.put(peer.id, peerToMap(peer));

  @override
  Future<void> delete(String id) => _box.delete(id);
}

/// Provides the [PeerRepository] backed by the encrypted `peers` box.
final Provider<PeerRepository> peerRepositoryProvider =
    Provider<PeerRepository>(
      (ref) => HivePeerRepository(ref.watch(appDatabaseProvider).peersBox),
    );
