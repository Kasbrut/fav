import 'package:fav/core/persistence/secure_store.dart';
import 'package:fav/features/profile/domain/client_profile_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// [ClientProfileRepository] backed by the OS keystore via [SecureStore].
///
/// The raw `.conf` text is stored under a per-server key; the file content
/// includes the client private key and PSK, so it never leaves the secure
/// store and is never logged.
class SecureClientProfileRepository implements ClientProfileRepository {
  /// Creates a [SecureClientProfileRepository] over [_store].
  const SecureClientProfileRepository(this._store);

  /// Key prefix used in the secure store; the suffix is the server id.
  static const String _keyPrefix = 'client_profile:';

  final SecureStore _store;

  String _key(String serverId) => '$_keyPrefix$serverId';

  @override
  Future<void> save({
    required String serverId,
    required String rawConf,
  }) {
    return _store.write(_key(serverId), rawConf);
  }

  @override
  Future<String?> getRaw(String serverId) => _store.read(_key(serverId));

  @override
  Future<void> delete(String serverId) => _store.delete(_key(serverId));
}

/// Provides the [ClientProfileRepository] backed by [SecureStore].
final Provider<ClientProfileRepository> clientProfileRepositoryProvider =
    Provider<ClientProfileRepository>(
      (ref) => SecureClientProfileRepository(ref.watch(secureStoreProvider)),
    );
