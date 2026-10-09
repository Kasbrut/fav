import 'dart:convert';

import 'package:fav/core/persistence/secure_store.dart';
import 'package:fav/features/settings/data/preferences_box.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';

const String _encryptionKeyName = 'db_encryption_key';
const String _serversBoxName = 'servers';
const String _runsBoxName = 'runs';
const String _scriptsBoxName = 'scripts';
const String _monitoringEventsBoxName = 'monitoring_events';
const String _peersBoxName = 'peers';

/// Resolves the AES key used to encrypt the local database.
///
/// On first run a 256-bit key is generated and stored in [store] (OS
/// Keystore / Keychain); later runs reuse the stored key. The key never
/// leaves secure storage and is never written to the database or the logs.
Future<List<int>> resolveDbEncryptionKey(SecureStore store) async {
  final stored = await store.read(_encryptionKeyName);
  if (stored != null) {
    try {
      return base64Decode(stored);
    } on FormatException {
      // Never rethrow the original: FormatException.toString() embeds its
      // source — the stored key material — and the boot-failure screen
      // renders the error (security audit H2 on the M10 flow).
      throw const FormatException('stored database key is not valid base64');
    }
  }
  final key = Hive.generateSecureKey();
  await store.write(_encryptionKeyName, base64Encode(key));
  return key;
}

/// Opens the encrypted `servers` box. Hive must already be initialized.
Future<Box<Map<dynamic, dynamic>>> openServersBox(SecureStore store) async {
  final key = await resolveDbEncryptionKey(store);
  return Hive.openBox<Map<dynamic, dynamic>>(
    _serversBoxName,
    encryptionCipher: HiveAesCipher(key),
  );
}

/// Opens the encrypted `runs` box. Hive must already be initialized.
Future<Box<Map<dynamic, dynamic>>> openRunsBox(SecureStore store) async {
  final key = await resolveDbEncryptionKey(store);
  return Hive.openBox<Map<dynamic, dynamic>>(
    _runsBoxName,
    encryptionCipher: HiveAesCipher(key),
  );
}

/// Opens the encrypted `scripts` box. Hive must already be initialized.
Future<Box<Map<dynamic, dynamic>>> openScriptsBox(SecureStore store) async {
  final key = await resolveDbEncryptionKey(store);
  return Hive.openBox<Map<dynamic, dynamic>>(
    _scriptsBoxName,
    encryptionCipher: HiveAesCipher(key),
  );
}

/// Opens the encrypted `monitoring_events` box (M15-T4). Hive must already
/// be initialized. Entries are connect/disconnect events pulled from the
/// server agent; retention is enforced by `MonitorEventsBox` in the
/// monitoring feature (7-day prune keyed on `serverTimestamp`, not the
/// device clock).
Future<Box<Map<dynamic, dynamic>>> openMonitoringEventsBox(
  SecureStore store,
) async {
  final key = await resolveDbEncryptionKey(store);
  return Hive.openBox<Map<dynamic, dynamic>>(
    _monitoringEventsBoxName,
    encryptionCipher: HiveAesCipher(key),
  );
}

/// Opens the encrypted `peers` box (multi-peer v1.1). Hive must already be
/// initialized. Each row holds the non-secret metadata for a WireGuard peer
/// (id, serverId, label, address, publicKey, createdAt); the matching .conf
/// (with the private key + PSK) lives in `flutter_secure_storage` under
/// `client_profile:<peerId>` (spec §10).
Future<Box<Map<dynamic, dynamic>>> openPeersBox(SecureStore store) async {
  final key = await resolveDbEncryptionKey(store);
  return Hive.openBox<Map<dynamic, dynamic>>(
    _peersBoxName,
    encryptionCipher: HiveAesCipher(key),
  );
}

/// Opened persistence resources for the running app.
class AppDatabase {
  /// Creates an [AppDatabase] over the given open boxes.
  AppDatabase({
    required this.serversBox,
    required this.runsBox,
    required this.scriptsBox,
    required this.monitoringEventsBox,
    required this.peersBox,
    required this.preferencesBox,
  });

  /// Encrypted box holding the registered servers.
  final Box<Map<dynamic, dynamic>> serversBox;

  /// Encrypted box holding the installation run history.
  final Box<Map<dynamic, dynamic>> runsBox;

  /// Encrypted box holding user-customized installer scripts.
  final Box<Map<dynamic, dynamic>> scriptsBox;

  /// Encrypted box holding per-peer connect/disconnect events (M15-T4).
  final Box<Map<dynamic, dynamic>> monitoringEventsBox;

  /// Encrypted box holding WireGuard peer metadata (multi-peer v1.1).
  final Box<Map<dynamic, dynamic>> peersBox;

  /// Encrypted box holding user preferences (theme, locale, recent errors).
  final Box<Map<dynamic, dynamic>> preferencesBox;
}

/// Initializes Hive and opens the encrypted database for the app.
///
/// Pass [secureStore] to override the storage backend (used in tests).
Future<AppDatabase> bootstrapAppDatabase({SecureStore? secureStore}) async {
  await Hive.initFlutter();
  final store = secureStore ?? createSecureStore();
  return AppDatabase(
    serversBox: await openServersBox(store),
    runsBox: await openRunsBox(store),
    scriptsBox: await openScriptsBox(store),
    monitoringEventsBox: await openMonitoringEventsBox(store),
    peersBox: await openPeersBox(store),
    preferencesBox: await openPreferencesBox(store),
  );
}

/// Provides the opened [AppDatabase]; must be overridden in `main()`.
final Provider<AppDatabase> appDatabaseProvider = Provider<AppDatabase>(
  (ref) => throw UnimplementedError('appDatabaseProvider must be overridden'),
);
