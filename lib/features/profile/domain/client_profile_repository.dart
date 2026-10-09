/// Persists the WireGuard client profile produced by an installation
/// (spec §8.6 — the client private key never leaves secure storage).
///
/// The repository stores the raw `.conf` text per server; the parsed
/// [ClientProfile][] is reconstructed on demand by [ClientProfileParser][]
/// so a schema change in our model does not invalidate stored profiles.
abstract interface class ClientProfileRepository {
  /// Stores [rawConf] for the server identified by [serverId].
  ///
  /// Overwrites any existing profile for that server.
  Future<void> save({required String serverId, required String rawConf});

  /// Returns the raw `.conf` text saved for [serverId], or `null` when no
  /// profile has been stored.
  Future<String?> getRaw(String serverId);

  /// Removes the saved profile for [serverId] (no-op if none exists).
  Future<void> delete(String serverId);
}
