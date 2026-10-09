import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Typed access to OS-backed secure storage (Keystore / Keychain).
///
/// Abstracted behind an interface so tests can inject an in-memory fake.
abstract interface class SecureStore {
  /// Reads the value stored under [key], or `null` if absent.
  Future<String?> read(String key);

  /// Writes [value] under [key].
  Future<void> write(String key, String value);

  /// Removes the value stored under [key].
  Future<void> delete(String key);
}

/// [SecureStore] backed by `flutter_secure_storage`.
class FlutterSecureStore implements SecureStore {
  /// Creates a [FlutterSecureStore] over the given storage backend.
  const FlutterSecureStore(this._storage);

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) {
    return _storage.write(key: key, value: value);
  }

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// The hardened production storage backend, shared by [createSecureStore]
/// and the bulk wipe (`AppResetService`), so `deleteAll` sweeps exactly the
/// store the app writes to — a divergence (e.g. a future `groupId` or
/// custom `service`) would silently leave secrets behind (security audit L1
/// on the wipe flow).
const FlutterSecureStorage kSecureStorageBackend = FlutterSecureStorage(
  iOptions: IOSOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
  ),
  mOptions: MacOsOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
  ),
);

/// Creates the production [SecureStore] with hardened platform options.
///
/// The Keychain item is device-bound (excluded from iCloud sync and backups);
/// Android already uses hardened storage by default in flutter_secure_storage
/// v10.
SecureStore createSecureStore() {
  return const FlutterSecureStore(kSecureStorageBackend);
}

/// Provides the application [SecureStore].
final Provider<SecureStore> secureStoreProvider = Provider<SecureStore>(
  (ref) => createSecureStore(),
);
