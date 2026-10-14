import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:fav/core/persistence/app_database.dart';
import 'package:fav/core/persistence/secure_store.dart';
import 'package:fav/features/servers/data/hive_server_repository.dart';
import 'package:fav/features/servers/domain/server.dart';
import 'package:fav/features/settings/application/backup_service.dart';
import 'package:fav/features/settings/data/backup_codec.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';

import '../../support/in_memory_secure_store.dart';

BackupCodec _codec() => BackupCodec(
  memoryKiB: 8 * 1024,
  iterations: 1,
  random: Random(42),
);

Future<AppDatabase> _database(String prefix) async {
  Future<Box<Map<dynamic, dynamic>>> box(String name) =>
      Hive.openBox<Map<dynamic, dynamic>>('${prefix}_$name');
  return AppDatabase(
    serversBox: await box('servers'),
    peersBox: await box('peers'),
    runsBox: await box('runs'),
    scriptsBox: await box('scripts'),
    preferencesBox: await box('preferences'),
    monitoringEventsBox: await box('monitoring'),
  );
}

// Synthetic secure-storage stand-in: survives termination of the worker.
class _PersistentTestStore implements SecureStore {
  _PersistentTestStore(this.box);
  final Box<String> box;
  @override
  Future<String?> read(String key) async => box.get(key);
  @override
  Future<void> write(String key, String value) async {
    await box.put(key, value);
    await box.flush();
    if (Platform.environment['FAV_AUDIT_STAGE'] == 'secure' &&
        key == 'client_profile:server-1') {
      await _terminate('secure');
    }
  }

  @override
  Future<void> delete(String key) async {
    if (!box.containsKey(key)) return;
    await box.delete(key);
    await box.flush();
    if (Platform.environment['FAV_AUDIT_STAGE'] == 'cleanup' &&
        key == 'backup_restore_undo') {
      await _terminate('cleanup');
    }
  }
}

Future<void> _terminate(String stage) async {
  stdout.writeln('AUDIT: terminated after durable $stage write');
  await stdout.flush();
  exit(73);
}

class _ExitAfterPut implements Box<Map<dynamic, dynamic>> {
  _ExitAfterPut(this.inner, this.kind);
  final Box<Map<dynamic, dynamic>> inner;
  final String kind;
  @override
  bool get isNotEmpty => inner.isNotEmpty;
  @override
  Map<dynamic, Map<dynamic, dynamic>> toMap() => inner.toMap();
  @override
  Map<dynamic, dynamic>? get(
    dynamic key, {
    Map<dynamic, dynamic>? defaultValue,
  }) => inner.get(key, defaultValue: defaultValue);
  @override
  Future<void> flush() => inner.flush();
  @override
  Future<void> put(dynamic key, Map<dynamic, dynamic> value) async {
    await inner.put(key, value);
    await inner.flush();
    final stage = Platform.environment['FAV_AUDIT_STAGE'];
    if ((kind == 'server' && stage == 'server') ||
        (kind == 'preferences' &&
            key == 'pending_backup_restore' &&
            stage == 'pending') ||
        (key == 'backup_restore_journal' && value['phase'] == stage)) {
      await _terminate(stage!);
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _restoreAndTerminate() async {
  Hive.init(Platform.environment['FAV_AUDIT_DIRECTORY']);
  final db = await _database('destination');
  final store = _PersistentTestStore(
    await Hive.openBox<String>('test_secrets'),
  );
  final interruptedDb = AppDatabase(
    serversBox: _ExitAfterPut(db.serversBox, 'server'),
    peersBox: db.peersBox,
    runsBox: db.runsBox,
    scriptsBox: db.scriptsBox,
    preferencesBox: _ExitAfterPut(db.preferencesBox, 'preferences'),
    monitoringEventsBox: db.monitoringEventsBox,
  );
  await BackupService(interruptedDb, store, codec: _codec()).restore(
    base64Decode(Platform.environment['FAV_AUDIT_BACKUP']!),
    'test password',
    rotateSshKeys: true,
    revokePeers: true,
  );
  fail('unexpected completion');
}

void main() {
  if (Platform.environment.containsKey('FAV_AUDIT_DIRECTORY')) {
    test('child restore process', _restoreAndTerminate);
    return;
  }
  for (final stage in [
    'preparing',
    'writing',
    'secure',
    'server',
    'pending',
    'online',
    'cleanup',
  ]) {
    test(
      'recovers abrupt restore termination at $stage',
      () async {
        final temp = Directory.systemTemp.createTempSync(
          'fav_restore_interrupt_',
        );
        try {
          Hive.init(temp.path);
          final sourceDb = await _database('source');
          final sourceStore = InMemorySecureStore();
          await HiveServerRepository(sourceDb.serversBox).save(
            Server(
              id: 'server-1',
              label: 'Synthetic server',
              host: 'vpn.example.invalid',
              sshPort: 22,
              username: 'admin',
              createdAt: DateTime.utc(2026, 10, 8),
            ),
          );
          await sourceStore.write(
            'client_profile:server-1',
            'synthetic profile',
          );
          final bytes = await BackupService(
            sourceDb,
            sourceStore,
            codec: _codec(),
          ).create('test password');
          await Hive.close();

          final flutterRoot = Platform.environment['FLUTTER_ROOT'];
          final flutterExecutable = flutterRoot == null
              ? 'flutter'
              : [flutterRoot, 'bin', 'flutter'].join(Platform.pathSeparator);
          final child = await Process.run(
            flutterExecutable,
            [
              'test',
              '--no-pub',
              'test/features/settings/backup_restore_interruption_test.dart',
            ],
            environment: {
              'FAV_AUDIT_DIRECTORY': temp.path,
              'FAV_AUDIT_BACKUP': base64Encode(bytes),
              'FAV_AUDIT_STAGE': stage,
            },
          ).timeout(const Duration(seconds: 45));
          expect(child.exitCode, isNot(0));
          expect(
            '${child.stdout}${child.stderr}',
            contains('AUDIT: terminated after durable $stage write'),
          );

          // A new service reads actual persisted files after worker death.
          final reopened = await _database('destination');
          final secrets = await Hive.openBox<String>('test_secrets');
          final fresh = BackupService(
            reopened,
            _PersistentTestStore(secrets),
            codec: _codec(),
          );
          final journal = reopened.preferencesBox.get(
            'backup_restore_journal',
          )!;
          expect(journal['rotateSshKeys'], isTrue);
          expect(journal['revokePeers'], isTrue);
          expect(jsonEncode(journal), isNot(contains('test password')));
          await fresh.recoverInterruptedRestore();
          await fresh.recoverInterruptedRestore();
          if (stage == 'online' || stage == 'cleanup') {
            expect(reopened.serversBox.length, 1);
            expect(secrets.get('client_profile:server-1'), 'synthetic profile');
          } else {
            expect(fresh.hasRestorableData, isFalse);
            expect(secrets.get('client_profile:server-1'), isNull);
            expect(fresh.pendingRestore, isNull);
            final retry = fresh.interruptedRestore!;
            expect(retry.rotateSshKeys, isTrue);
            expect(retry.revokePeers, isTrue);
            await fresh.restore(
              bytes,
              'test password',
              rotateSshKeys: retry.rotateSshKeys,
              revokePeers: retry.revokePeers,
            );
          }
          expect(fresh.pendingRestore?.serverIds, ['server-1']);
          expect(fresh.pendingRestore?.rotateSshKeys, isTrue);
          expect(fresh.pendingRestore?.revokePeers, isTrue);
          expect(reopened.preferencesBox.get('backup_restore_journal'), isNull);
          expect(secrets.get('backup_restore_undo'), isNull);
        } finally {
          await Hive.close();
          temp.deleteSync(recursive: true);
        }
      },
    );
  }
}
