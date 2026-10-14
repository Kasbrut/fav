import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:fav/core/persistence/app_database.dart';
import 'package:fav/features/install/data/keys/ssh_key_repository.dart';
import 'package:fav/features/install/data/ssh/host_key_store.dart';
import 'package:fav/features/peers/data/hive_peer_repository.dart';
import 'package:fav/features/peers/data/secure_peer_secret_repository.dart';
import 'package:fav/features/peers/domain/peer.dart';
import 'package:fav/features/servers/data/hive_server_repository.dart';
import 'package:fav/features/servers/domain/host_key_fingerprint.dart';
import 'package:fav/features/servers/domain/server.dart';
import 'package:fav/features/settings/application/backup_service.dart';
import 'package:fav/features/settings/data/backup_codec.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';

import '../../support/in_memory_secure_store.dart';

class _FailingStore extends InMemorySecureStore {
  bool failRestore = false;
  bool failCleanup = false;
  bool failRollback = false;

  @override
  Future<void> write(String key, String value) async {
    await super.write(key, value);
    if (failRestore && key == 'client_profile:server-1') {
      failRestore = false;
      throw StateError('write failed after mutation');
    }
  }

  @override
  Future<void> delete(String key) async {
    await super.delete(key);
    if ((failCleanup && key == 'backup_restore_undo') ||
        (failRollback && key == 'client_profile:server-1')) {
      failCleanup = false;
      failRollback = false;
      throw StateError('interrupted cleanup');
    }
  }
}

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('fav_backup_test_');
    Hive.init(tempDir.path);
  });

  tearDown(() async {
    await Hive.close();
    tempDir.deleteSync(recursive: true);
  });

  Future<AppDatabase> database(String prefix) async {
    Future<Box<Map<dynamic, dynamic>>> box(String name) =>
        Hive.openBox<Map<dynamic, dynamic>>('${prefix}_$name');
    return AppDatabase(
      serversBox: await box('servers'),
      runsBox: await box('runs'),
      scriptsBox: await box('scripts'),
      monitoringEventsBox: await box('monitoring'),
      peersBox: await box('peers'),
      preferencesBox: await box('preferences'),
    );
  }

  BackupCodec codec() => BackupCodec(
    memoryKiB: 8 * 1024,
    iterations: 1,
    random: Random(42),
  );

  test(
    'restores server, trust anchor, SSH identity and peer profile',
    () async {
      final sourceDb = await database('source');
      final sourceStore = InMemorySecureStore();
      final server = Server(
        id: 'server-1',
        label: 'Test server',
        host: 'vpn.example.com',
        sshPort: 22,
        username: 'admin',
        sshKeyId: 'server-1',
        createdAt: DateTime.utc(2026, 10, 8),
      );
      final peer = Peer(
        id: 'peer-1',
        serverId: server.id,
        label: 'Phone',
        address: '10.13.13.2/32',
        publicKey: '${List.filled(43, 'A').join()}=',
        createdAt: DateTime.utc(2026, 10, 8),
      );
      await HiveServerRepository(sourceDb.serversBox).save(server);
      await HivePeerRepository(sourceDb.peersBox).save(peer);
      await SecureSshKeyRepository(sourceStore).getOrCreate(
        serverId: server.id,
        comment: 'fav@server-1',
      );
      await HostKeyStore(sourceStore).pin(
        HostKeyFingerprint(
          host: server.host,
          port: server.sshPort,
          keyType: 'ssh-ed25519',
          hashAlgorithm: 'sha256',
          fingerprint: 'fingerprint',
          pinnedAt: DateTime.utc(2026, 10, 8),
        ),
      );
      await SecurePeerSecretRepository(
        sourceStore,
      ).save(peerId: peer.id, rawConf: '[Interface]\nPrivateKey = secret');

      final source = BackupService(sourceDb, sourceStore, codec: codec());
      final bytes = await source.create('a strong backup password');

      final destinationDb = await database('destination');
      final destinationStore = InMemorySecureStore();
      final destination = BackupService(
        destinationDb,
        destinationStore,
        codec: codec(),
      );
      final summary = await destination.restore(
        bytes,
        'a strong backup password',
      );

      expect(summary.serverCount, 1);
      expect(summary.peerCount, 1);
      expect(
        await HiveServerRepository(destinationDb.serversBox).getById(server.id),
        isNotNull,
      );
      expect(
        await HostKeyStore(
          destinationStore,
        ).lookup(server.host, server.sshPort),
        isNotNull,
      );
      expect(
        await SecureSshKeyRepository(destinationStore).get(server.id),
        isNotNull,
      );
      expect(
        await SecurePeerSecretRepository(destinationStore).read(peer.id),
        contains('PrivateKey'),
      );
    },
  );

  test('refuses to merge into an installation containing data', () async {
    final db = await database('occupied');
    await db.scriptsBox.put('custom', <String, Object?>{'id': 'custom'});
    final service = BackupService(
      db,
      InMemorySecureStore(),
      codec: codec(),
    );

    expect(service.hasRestorableData, isTrue);
  });

  test('persists and completes resumable online verification', () async {
    final db = await database('pending');
    final service = BackupService(
      db,
      InMemorySecureStore(),
      codec: codec(),
    );

    await service.beginOnlineRestore(
      serverIds: const ['one', 'two'],
      rotateSshKeys: true,
      revokePeers: true,
    );
    expect(service.pendingRestore?.serverIds, ['one', 'two']);
    await service.recoverInterruptedRestore(); // Legacy marker has no journal.
    expect(service.pendingRestore?.rotateSshKeys, isTrue);
    expect(service.pendingRestore?.revokePeers, isTrue);

    await service.completeOnlineRestoreFor('one');
    expect(service.pendingRestore?.serverIds, ['two']);

    await service.completeOnlineRestoreFor('two');
    expect(service.pendingRestore, isNull);
  });

  test(
    'ordinary write failure rolls back originals and retains options',
    () async {
      final sourceDb = await database('source');
      final sourceStore = InMemorySecureStore();
      await sourceStore.write('client_profile:server-1', 'new profile');
      await HiveServerRepository(sourceDb.serversBox).save(
        Server(
          id: 'server-1',
          label: 'Test',
          host: 'vpn.example.com',
          sshPort: 22,
          username: 'admin',
          createdAt: DateTime.utc(2026, 10, 8),
        ),
      );
      final bytes = await BackupService(
        sourceDb,
        sourceStore,
        codec: codec(),
      ).create('backup password');
      final db = await database('destination');
      await db.preferencesBox.put('existing', {'themeMode': 'dark'});
      final store = _FailingStore();
      await store.write('client_profile:server-1', 'original profile');
      store.failRestore = true;
      final service = BackupService(db, store, codec: codec());
      await expectLater(
        service.restore(
          bytes,
          'backup password',
          rotateSshKeys: true,
          revokePeers: true,
        ),
        throwsStateError,
      );
      expect(service.hasRestorableData, isFalse);
      expect(await store.read('client_profile:server-1'), 'original profile');
      expect(db.preferencesBox.get('existing'), {'themeMode': 'dark'});
      expect(service.interruptedRestore?.rotateSshKeys, isTrue);
      expect(service.interruptedRestore?.revokePeers, isTrue);
      expect(await store.read('backup_restore_undo'), isNull);
    },
  );

  for (final duringRollback in [true, false]) {
    test(
      'repeats interrupted recovery cleanup (rollback=$duringRollback)',
      () async {
        final db = await database('recovery');
        final store = _FailingStore();
        await db.serversBox.put('partial', {'id': 'partial'});
        await store.write('client_profile:server-1', 'partial profile');
        await store.write(
          'backup_restore_undo',
          jsonEncode({
            'client_profile:server-1': null,
          }),
        );
        await db.preferencesBox.put('backup_restore_journal', {
          'phase': 'writing',
          'rotateSshKeys': true,
          'revokePeers': true,
          'preferences': <dynamic>[],
        });
        store
          ..failRollback = duringRollback
          ..failCleanup = !duringRollback;
        await expectLater(
          BackupService(db, store).recoverInterruptedRestore(),
          throwsStateError,
        );
        final fresh = BackupService(db, store);
        await fresh.recoverInterruptedRestore();
        await fresh.recoverInterruptedRestore();
        expect(fresh.hasRestorableData, isFalse);
        expect(fresh.interruptedRestore?.rotateSshKeys, isTrue);
        expect(fresh.interruptedRestore?.revokePeers, isTrue);
        expect(await store.read('client_profile:server-1'), isNull);
        expect(await store.read('backup_restore_undo'), isNull);
      },
    );
  }
}
