/// Persists the raw WireGuard `.conf` for each peer (multi-peer v1.1).
///
/// The conf includes the client private key and the PSK; entries live in
/// `flutter_secure_storage` and never appear in any other store, log or
/// error message (spec §10).
abstract interface class PeerSecretRepository {
  /// Stores [rawConf] for [peerId]. Overwrites any existing entry.
  Future<void> save({required String peerId, required String rawConf});

  /// Returns the raw `.conf` for [peerId], or `null` when none is stored.
  Future<String?> read(String peerId);

  /// Removes the entry for [peerId]. No-op when none exists.
  Future<void> delete(String peerId);
}
