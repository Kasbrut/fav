import 'package:fav/features/peers/domain/peer.dart';
import 'package:fav/features/peers/domain/peer_repository.dart';

/// In-memory test fake of [PeerRepository] used by widget and unit tests
/// that need to override `peerRepositoryProvider`.
class StaticPeerRepository implements PeerRepository {
  StaticPeerRepository(this._peers);
  final List<Peer> _peers;

  @override
  Future<List<Peer>> getAll() async => _peers;

  @override
  Future<Peer?> getById(String id) async {
    final m = _peers.where((p) => p.id == id);
    return m.isEmpty ? null : m.first;
  }

  @override
  Future<List<Peer>> getByServerId(String serverId) async =>
      _peers.where((p) => p.serverId == serverId).toList();

  @override
  Future<void> save(Peer peer) async {}

  @override
  Future<void> delete(String id) async {}
}
