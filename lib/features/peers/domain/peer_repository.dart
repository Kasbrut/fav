import 'package:fav/features/peers/domain/peer.dart';

/// Persists the non-secret metadata of WireGuard peers (multi-peer v1.1).
///
/// The matching `.conf` (with the private key + PSK) lives in
/// `PeerSecretRepository`, never on a [Peer]; see spec §10.
abstract interface class PeerRepository {
  /// Returns every known peer, ordered by `createdAt` ascending so the
  /// oldest entry — peer #0 in the multi-peer model — is at index 0.
  Future<List<Peer>> getAll();

  /// Returns the peer identified by [id], or `null` if unknown.
  Future<Peer?> getById(String id);

  /// Returns the peers belonging to [serverId], ordered by `createdAt`
  /// ascending (so the first-installed client is at index 0).
  Future<List<Peer>> getByServerId(String serverId);

  /// Inserts or updates the given [peer].
  Future<void> save(Peer peer);

  /// Removes the peer identified by [id]. No-op when no entry matches.
  Future<void> delete(String id);
}
