import 'dart:convert';
import 'dart:typed_data';

import 'package:fav/core/persistence/app_database.dart';
import 'package:fav/core/persistence/secure_store.dart';
import 'package:fav/features/install/data/keys/ssh_key_repository.dart';
import 'package:fav/features/install/data/run_mappers.dart';
import 'package:fav/features/install/data/scripts/user_script_mappers.dart';
import 'package:fav/features/install/data/ssh/host_key_store.dart';
import 'package:fav/features/peers/data/hive_peer_repository.dart';
import 'package:fav/features/peers/data/peer_mappers.dart';
import 'package:fav/features/peers/data/secure_peer_secret_repository.dart';
import 'package:fav/features/profile/data/secure_client_profile_repository.dart';
import 'package:fav/features/servers/data/hive_server_repository.dart';
import 'package:fav/features/servers/data/server_mappers.dart';
import 'package:fav/features/settings/data/backup_codec.dart';
import 'package:fav/features/settings/domain/user_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive_ce.dart';

const String _pendingRestoreKey = 'pending_backup_restore';

/// Summary shown before and after restoring a backup.
class BackupSummary {
  /// Creates a backup summary.
  const BackupSummary({
    required this.createdAt,
    required this.serverCount,
    required this.peerCount,
  });

  /// Time recorded by the source device.
  final DateTime createdAt;

  /// Number of server records in the backup.
  final int serverCount;

  /// Number of peer records in the backup.
  final int peerCount;
}

/// Online work still required after local backup data was restored.
class PendingRestore {
  /// Creates pending restore state.
  const PendingRestore({
    required this.serverIds,
    required this.rotateSshKeys,
    required this.revokePeers,
  });

  /// Servers whose connection check or selected recovery work is incomplete.
  final List<String> serverIds;

  /// Whether restored FAV SSH identities must be replaced.
  final bool rotateSshKeys;

  /// Whether all existing remote peers must be revoked.
  final bool revokePeers;
}

/// Creates and restores encrypted, portable FAV backups.
class BackupService {
  /// Creates a service over the app's persistence stores.
  BackupService(
    this._database,
    this._secureStore, {
    BackupCodec? codec,
  }) : _codec = codec ?? BackupCodec();

  final AppDatabase _database;
  final SecureStore _secureStore;
  final BackupCodec _codec;

  /// Whether application state already exists and therefore cannot be merged.
  bool get hasRestorableData =>
      _database.serversBox.isNotEmpty ||
      _database.peersBox.isNotEmpty ||
      _database.runsBox.isNotEmpty ||
      _database.scriptsBox.isNotEmpty;

  /// Pending online verification, if a restore has not fully completed.
  PendingRestore? get pendingRestore {
    final raw = _database.preferencesBox.get(_pendingRestoreKey);
    if (raw == null) return null;
    try {
      return PendingRestore(
        serverIds: (raw['serverIds'] as List<dynamic>).cast<String>(),
        rotateSshKeys: raw['rotateSshKeys'] as bool,
        revokePeers: raw['revokePeers'] as bool,
      );
    } on Object {
      return null;
    }
  }

  /// Starts the resumable online phase of a restore.
  Future<void> beginOnlineRestore({
    required Iterable<String> serverIds,
    required bool rotateSshKeys,
    required bool revokePeers,
  }) async {
    final ids = serverIds.toList();
    if (ids.isEmpty) {
      await _database.preferencesBox.delete(_pendingRestoreKey);
      return;
    }
    return _database.preferencesBox.put(_pendingRestoreKey, {
      'serverIds': ids,
      'rotateSshKeys': rotateSshKeys,
      'revokePeers': revokePeers,
    });
  }

  /// Marks one server complete and removes the session after the final server.
  Future<void> completeOnlineRestoreFor(String serverId) async {
    final pending = pendingRestore;
    if (pending == null) return;
    final remaining = pending.serverIds.where((id) => id != serverId).toList();
    if (remaining.isEmpty) {
      await _database.preferencesBox.delete(_pendingRestoreKey);
      return;
    }
    await beginOnlineRestore(
      serverIds: remaining,
      rotateSshKeys: pending.rotateSshKeys,
      revokePeers: pending.revokePeers,
    );
  }

  /// Builds an authenticated encrypted backup.
  Future<Uint8List> create(String password) async {
    final servers = await HiveServerRepository(_database.serversBox).getAll();
    final peers = await HivePeerRepository(_database.peersBox).getAll();
    final hostKeys = HostKeyStore(_secureStore);
    final sshKeys = SecureSshKeyRepository(_secureStore);
    final peerSecrets = SecurePeerSecretRepository(_secureStore);
    final legacyProfiles = SecureClientProfileRepository(_secureStore);

    final pins = <String, Object?>{};
    final keySeeds = <String, Object?>{};
    final profiles = <String, Object?>{};
    final legacy = <String, Object?>{};
    for (final server in servers) {
      final pin = await hostKeys.lookup(server.host, server.sshPort);
      if (pin != null) {
        pins[server.id] = <String, Object?>{
          'host': pin.host,
          'port': pin.port,
          'keyType': pin.keyType,
          'hashAlgorithm': pin.hashAlgorithm,
          'fingerprint': pin.fingerprint,
          'pinnedAt': pin.pinnedAt.toIso8601String(),
        };
      }
      final keyId = server.sshKeyId;
      if (keyId != null) {
        final pair = await sshKeys.get(keyId);
        if (pair != null) keySeeds[keyId] = base64Encode(pair.seedBytes);
      }
      final oldProfile = await legacyProfiles.getRaw(server.id);
      if (oldProfile != null) legacy[server.id] = oldProfile;
    }
    for (final peer in peers) {
      final profile = await peerSecrets.read(peer.id);
      if (profile != null) profiles[peer.id] = profile;
    }

    final preferences = _database.preferencesBox.toMap()
      ..remove(_pendingRestoreKey);
    final sanitizedPreferences = <Object?, Map<dynamic, dynamic>>{};
    for (final entry in preferences.entries) {
      final value = Map<dynamic, dynamic>.from(entry.value)
        ..['appLockEnabled'] = false
        ..['recentErrors'] = <Object?>[];
      sanitizedPreferences[entry.key] = value;
    }

    final payload = <String, Object?>{
      'schemaVersion': 1,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'boxes': <String, Object?>{
        'servers': _rows(_database.serversBox),
        'peers': _rows(_database.peersBox),
        'runs': _safeRunRows(_rows(_database.runsBox)),
        'scripts': _rows(_database.scriptsBox),
        'preferences': _mapRows(sanitizedPreferences),
      },
      'secure': <String, Object?>{
        'hostKeys': pins,
        'sshKeySeeds': keySeeds,
        'peerProfiles': profiles,
        'legacyProfiles': legacy,
      },
    };
    return _codec.encrypt(payload: payload, password: password);
  }

  /// Summarizes the data that a newly created backup will contain.
  Future<BackupSummary> summarizeCurrentData() async {
    final servers = await HiveServerRepository(_database.serversBox).getAll();
    final peers = await HivePeerRepository(_database.peersBox).getAll();
    return BackupSummary(
      createdAt: DateTime.now().toUtc(),
      serverCount: servers.length,
      peerCount: peers.length,
    );
  }

  /// Reads summary metadata without modifying local state.
  Future<BackupSummary> inspect(List<int> bytes, String password) async {
    final payload = await _codec.decrypt(bytes: bytes, password: password);
    _validate(payload);
    final boxes = payload['boxes'] as Map<String, dynamic>;
    return BackupSummary(
      createdAt: DateTime.parse(payload['createdAt'] as String),
      serverCount: (boxes['servers'] as List<dynamic>).length,
      peerCount: (boxes['peers'] as List<dynamic>).length,
    );
  }

  /// Restores a backup into an empty installation.
  Future<BackupSummary> restore(
    List<int> bytes,
    String password, {
    bool rotateSshKeys = false,
    bool revokePeers = false,
  }) async {
    if (hasRestorableData) {
      throw const BackupFormatException('restore requires an empty app');
    }
    final payload = await _codec.decrypt(bytes: bytes, password: password);
    _validate(payload);
    final boxes = payload['boxes'] as Map<String, dynamic>;
    final secure = payload['secure'] as Map<String, dynamic>;
    final writtenSecureKeys = <String>[];
    try {
      await _restoreSecure(secure, writtenSecureKeys);
      await _putRows(_database.serversBox, boxes['servers'] as List<dynamic>);
      await _putRows(_database.peersBox, boxes['peers'] as List<dynamic>);
      await _putRows(
        _database.runsBox,
        _safeRunRows(boxes['runs'] as List<dynamic>),
      );
      await _putRows(_database.scriptsBox, boxes['scripts'] as List<dynamic>);
      await _putRows(
        _database.preferencesBox,
        _sanitizedPreferenceRows(boxes['preferences'] as List<dynamic>),
      );
      final serverIds = _validatedRows(
        boxes['servers'] as List<dynamic>,
      ).map((row) => serverFromMap(row.value).id);
      await beginOnlineRestore(
        serverIds: serverIds,
        rotateSshKeys: rotateSshKeys,
        revokePeers: revokePeers,
      );
    } on Object {
      await _database.serversBox.clear();
      await _database.peersBox.clear();
      await _database.runsBox.clear();
      await _database.scriptsBox.clear();
      await _database.preferencesBox.clear();
      for (final key in writtenSecureKeys) {
        await _secureStore.delete(key);
      }
      rethrow;
    }
    return BackupSummary(
      createdAt: DateTime.parse(payload['createdAt'] as String),
      serverCount: (boxes['servers'] as List<dynamic>).length,
      peerCount: (boxes['peers'] as List<dynamic>).length,
    );
  }

  List<Map<String, Object?>> _rows(Box<Map<dynamic, dynamic>> box) =>
      _mapRows(box.toMap());

  List<dynamic> _safeRunRows(List<dynamic> rows) {
    return rows.map((rowValue) {
      final row = Map<String, dynamic>.from(rowValue as Map);
      final value = Map<String, dynamic>.from(row['value'] as Map);
      if (value['status'] == 'running' || value['status'] == 'queued') {
        value['status'] = 'orphaned';
      }
      row['value'] = value;
      return row;
    }).toList();
  }

  List<Map<String, Object?>> _mapRows(
    Map<Object?, Map<dynamic, dynamic>> values,
  ) => values.entries
      .map(
        (entry) => <String, Object?>{
          'key': entry.key.toString(),
          'value': _jsonMap(entry.value),
        },
      )
      .toList();

  Map<String, Object?> _jsonMap(Map<dynamic, dynamic> value) => value.map(
    (key, item) => MapEntry(key.toString(), _jsonValue(item)),
  );

  Object? _jsonValue(Object? value) {
    if (value is Map<dynamic, dynamic>) return _jsonMap(value);
    if (value is List<dynamic>) return value.map(_jsonValue).toList();
    if (value == null || value is String || value is num || value is bool) {
      return value;
    }
    throw const BackupFormatException('unsupported stored value');
  }

  void _validate(Map<String, dynamic> payload) {
    if (payload['schemaVersion'] != 1 ||
        payload['createdAt'] is! String ||
        payload['boxes'] is! Map<String, dynamic> ||
        payload['secure'] is! Map<String, dynamic>) {
      throw const BackupFormatException('unsupported backup contents');
    }
    final boxes = payload['boxes'] as Map<String, dynamic>;
    for (final name in ['servers', 'peers', 'runs', 'scripts', 'preferences']) {
      if (boxes[name] is! List<dynamic>) {
        throw const BackupFormatException('incomplete backup contents');
      }
    }
    try {
      final servers = _validatedRows(boxes['servers'] as List<dynamic>);
      final peers = _validatedRows(boxes['peers'] as List<dynamic>);
      final runs = _validatedRows(boxes['runs'] as List<dynamic>);
      final scripts = _validatedRows(boxes['scripts'] as List<dynamic>);
      final preferences = _validatedRows(
        boxes['preferences'] as List<dynamic>,
      );
      if (servers.length > 1000 || peers.length > 10000) {
        throw const BackupFormatException('backup contains too many records');
      }
      final serverIds = servers
          .map((row) => serverFromMap(row.value).id)
          .toSet();
      for (final row in peers) {
        final peer = peerFromMap(row.value);
        if (!serverIds.contains(peer.serverId)) {
          throw const BackupFormatException('backup contains an orphan peer');
        }
      }
      for (final row in runs) {
        runFromMap(row.value);
      }
      for (final row in scripts) {
        userScriptFromMap(row.value);
      }
      for (final row in preferences) {
        UserPreferences.fromJson(row.value);
      }
      DateTime.parse(payload['createdAt'] as String);
    } on BackupFormatException {
      rethrow;
    } on Object {
      throw const BackupFormatException('invalid backup contents');
    }
  }

  List<MapEntry<String, Map<dynamic, dynamic>>> _validatedRows(
    List<dynamic> rows,
  ) {
    final result = <MapEntry<String, Map<dynamic, dynamic>>>[];
    final keys = <String>{};
    for (final rowValue in rows) {
      if (rowValue is! Map<String, dynamic> ||
          rowValue['key'] is! String ||
          rowValue['value'] is! Map<String, dynamic>) {
        throw const BackupFormatException('invalid backup row');
      }
      final key = rowValue['key'] as String;
      if (key.isEmpty || !keys.add(key)) {
        throw const BackupFormatException('invalid backup row key');
      }
      result.add(
        MapEntry(key, rowValue['value'] as Map<String, dynamic>),
      );
    }
    return result;
  }

  List<dynamic> _sanitizedPreferenceRows(List<dynamic> rows) {
    return rows.map((rowValue) {
      final row = Map<String, dynamic>.from(rowValue as Map<String, dynamic>);
      final value =
          Map<String, dynamic>.from(
              row['value'] as Map<String, dynamic>,
            )
            ..['appLockEnabled'] = false
            ..['recentErrors'] = <Object?>[];
      row['value'] = value;
      return row;
    }).toList();
  }

  Future<void> _restoreSecure(
    Map<String, dynamic> secure,
    List<String> written,
  ) async {
    Future<void> write(String key, String value) async {
      await _secureStore.write(key, value);
      written.add(key);
    }

    final pins = secure['hostKeys'] as Map<String, dynamic>? ?? const {};
    for (final raw in pins.values) {
      final pin = raw as Map<String, dynamic>;
      final key = 'hostkey:${pin['host']}:${pin['port']}';
      await write(key, jsonEncode(pin));
    }
    final seeds = secure['sshKeySeeds'] as Map<String, dynamic>? ?? const {};
    for (final entry in seeds.entries) {
      final decoded = base64Decode(entry.value as String);
      if (decoded.length != 32) {
        throw const BackupFormatException('invalid SSH key in backup');
      }
      await write('ssh-key:${entry.key}', entry.value as String);
    }
    final profiles =
        secure['peerProfiles'] as Map<String, dynamic>? ?? const {};
    for (final entry in profiles.entries) {
      await write('client_profile:${entry.key}', entry.value as String);
    }
    final legacy =
        secure['legacyProfiles'] as Map<String, dynamic>? ?? const {};
    for (final entry in legacy.entries) {
      await write('client_profile:${entry.key}', entry.value as String);
    }
  }

  Future<void> _putRows(
    Box<Map<dynamic, dynamic>> box,
    List<dynamic> rows,
  ) async {
    for (final rowValue in rows) {
      final row = rowValue as Map<String, dynamic>;
      final value = row['value'];
      if (row['key'] is! String || value is! Map<String, dynamic>) {
        throw const BackupFormatException('invalid backup row');
      }
      await box.put(row['key'] as String, value);
    }
  }
}

/// Provides backup creation and restoration.
final Provider<BackupService> backupServiceProvider = Provider<BackupService>(
  (ref) => BackupService(
    ref.watch(appDatabaseProvider),
    ref.watch(secureStoreProvider),
  ),
);
