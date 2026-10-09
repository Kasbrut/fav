import 'package:fav/core/persistence/secure_store.dart';
import 'package:fav/features/peers/domain/peer_secret_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// [PeerSecretRepository] backed by the OS keystore via [SecureStore].
///
/// The raw `.conf` for each peer (containing the private key and PSK) is
/// stored under `client_profile:<peerId>`. The legacy v1.0 layout used
/// `client_profile:<serverId>`; the migrator promotes those entries to
/// the per-peer key as part of the v1.1 upgrade.
class SecurePeerSecretRepository implements PeerSecretRepository {
  /// Creates a [SecurePeerSecretRepository] over [_store].
  const SecurePeerSecretRepository(this._store);

  /// Key prefix used in the secure store; the suffix is the peer id.
  static const String _keyPrefix = 'client_profile:';

  final SecureStore _store;

  String _key(String peerId) => '$_keyPrefix$peerId';

  @override
  Future<void> save({required String peerId, required String rawConf}) {
    return _store.write(_key(peerId), rawConf);
  }

  @override
  Future<String?> read(String peerId) => _store.read(_key(peerId));

  @override
  Future<void> delete(String peerId) => _store.delete(_key(peerId));
}

/// Provides the [PeerSecretRepository] backed by the OS keystore.
final Provider<PeerSecretRepository> peerSecretRepositoryProvider =
    Provider<PeerSecretRepository>(
      (ref) => SecurePeerSecretRepository(ref.watch(secureStoreProvider)),
    );
