import 'package:fav/core/persistence/secure_store.dart';
import 'package:fav/core/utils/app_logger.dart';
import 'package:fav/features/peers/domain/peer.dart';
import 'package:fav/features/peers/domain/peer_repository.dart';
import 'package:fav/features/peers/domain/peer_secret_repository.dart';
import 'package:fav/features/profile/data/client_profile_parser.dart';
import 'package:fav/features/servers/domain/server_repository.dart';
import 'package:logger/logger.dart';
import 'package:uuid/uuid.dart';

/// Migrates the v1.0 single-client storage layout (one
/// `client_profile:<serverId>` entry per server in the OS keystore) to the
/// v1.1 multi-peer layout (a [Peer] row in the encrypted Hive box + the raw
/// `.conf` keyed by `client_profile:<peerId>` in the OS keystore).
///
/// Idempotent: the per-server gate is "does the peers box already contain a
/// row for this serverId?". Re-running the migrator is a no-op.
///
/// The "First client" label is provided by the caller (resolved against
/// AppLocalizations) so the migrator stays free of widget concerns.
class LegacyPeerMigrator {
  /// Creates a [LegacyPeerMigrator].
  LegacyPeerMigrator({
    required this._serverRepository,
    required this._peerRepository,
    required this._peerSecretRepository,
    required this._secureStore,
    Uuid? uuid,
    DateTime Function()? clock,
    this._parser = const ClientProfileParser(),
    Logger? logger,
  }) : _uuid = uuid ?? const Uuid(),
       _clock = clock ?? DateTime.now,
       _logger = logger ?? appLogger;

  final ServerRepository _serverRepository;
  final PeerRepository _peerRepository;
  final PeerSecretRepository _peerSecretRepository;
  final SecureStore _secureStore;
  final Uuid _uuid;
  final DateTime Function() _clock;
  final ClientProfileParser _parser;
  final Logger _logger;

  static const String _legacyKeyPrefix = 'client_profile:';

  /// Runs the migration once for every server whose legacy entry has not
  /// already been promoted into the peers box. Returns the number of new
  /// peer rows created (0 on no-op).
  ///
  /// [firstClientLabel] is what the migrated peer's label will be set to —
  /// the caller resolves it from `AppLocalizations` (`peerFirstClientLabel`).
  Future<int> migrate({required String firstClientLabel}) async {
    final servers = await _serverRepository.getAll();
    var migrated = 0;
    for (final server in servers) {
      final legacyKey = '$_legacyKeyPrefix${server.id}';
      final existing = await _peerRepository.getByServerId(server.id);
      if (existing.isNotEmpty) {
        // Already migrated on a previous run. A leftover legacy entry here
        // would mean the previous run's `_secureStore.delete` failed after
        // the peer row landed — opportunistically retire it so secrets do
        // not live in two places (audit M-1).
        final stale = await _secureStore.read(legacyKey);
        if (stale != null) {
          await _secureStore.delete(legacyKey);
          _logger.i(
            'Removed stale legacy client profile for server ${server.id}',
          );
        }
        continue;
      }
      final rawConf = await _secureStore.read(legacyKey);
      if (rawConf == null || rawConf.isEmpty) {
        continue;
      }
      final peerId = _uuid.v4();
      try {
        final profile = await _parser.parse(rawConf);
        final peer = Peer(
          id: peerId,
          serverId: server.id,
          label: firstClientLabel,
          address: profile.address,
          publicKey: profile.clientPublicKey,
          createdAt: _clock(),
        );
        await _peerSecretRepository.save(peerId: peerId, rawConf: rawConf);
        await _peerRepository.save(peer);
        await _secureStore.delete(legacyKey);
        migrated++;
        _logger.i('Migrated legacy client profile for server ${server.id}');
      } on Object catch (error) {
        // A single corrupt entry must not block the migration of others.
        // Compensate any partial write: an orphan secret with no Hive row
        // would accumulate one new keychain entry on every restart (audit
        // M-2). Best-effort delete; ignore failures, they're surfaced via
        // the logger only.
        try {
          await _peerSecretRepository.delete(peerId);
        } on Object catch (cleanupError) {
          _logger.w(
            'Cleanup of orphan secret $peerId failed: $cleanupError',
          );
        }
        _logger.w(
          'Skipping legacy client profile for server ${server.id}: '
          '${error.runtimeType}',
        );
      }
    }
    return migrated;
  }
}
