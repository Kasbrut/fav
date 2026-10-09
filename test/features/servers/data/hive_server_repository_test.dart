import 'dart:io';

import 'package:fav/core/persistence/app_database.dart';
import 'package:fav/features/servers/data/hive_server_repository.dart';
import 'package:fav/features/servers/domain/server.dart';
import 'package:fav/features/settings/data/preferences_box.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';

import '../../../support/in_memory_secure_store.dart';

/// Tests for [HiveServerRepository] on an encrypted Hive box.
void main() {
  late Directory tempDir;
  late InMemorySecureStore secureStore;
  late Box<Map<dynamic, dynamic>> box;
  late HiveServerRepository repository;

  Server buildServer(String id) => Server(
    id: id,
    label: 'server-$id',
    host: '203.0.113.5',
    sshPort: 22,
    username: 'root',
    createdAt: DateTime(2026, 5, 18),
  );

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('wg_repo_test');
    Hive.init(tempDir.path);
    secureStore = InMemorySecureStore();
    box = await openServersBox(secureStore);
    repository = HiveServerRepository(box);
  });

  tearDown(() async {
    await Hive.close();
    tempDir.deleteSync(recursive: true);
  });

  test('save then getAll returns the stored server', () async {
    await repository.save(buildServer('a'));
    final all = await repository.getAll();
    expect(all, hasLength(1));
    expect(all.first.id, 'a');
  });

  test('getById returns the matching server, or null when absent', () async {
    await repository.save(buildServer('a'));
    expect((await repository.getById('a'))?.id, 'a');
    expect(await repository.getById('missing'), isNull);
  });

  test('save updates an already stored server', () async {
    await repository.save(buildServer('a'));
    await repository.save(buildServer('a').copyWith(label: 'renamed'));
    final all = await repository.getAll();
    expect(all, hasLength(1));
    expect(all.first.label, 'renamed');
  });

  test('delete removes the server', () async {
    await repository.save(buildServer('a'));
    await repository.delete('a');
    expect(await repository.getAll(), isEmpty);
  });

  test('servers survive reopening the encrypted box', () async {
    await repository.save(buildServer('a'));
    await box.close();
    final reopened = await openServersBox(secureStore);
    final all = await HiveServerRepository(reopened).getAll();
    expect(all.single.id, 'a');
  });

  test('the database file holds no plaintext server data', () async {
    await repository.save(buildServer('amsterdam'));
    await Hive.close();
    final bytes = await File('${tempDir.path}/servers.hive').readAsBytes();
    final raw = String.fromCharCodes(bytes);
    expect(raw.contains('server-amsterdam'), isFalse);
    expect(raw.contains('203.0.113.5'), isFalse);
  });

  test('serverRepositoryProvider yields a HiveServerRepository', () async {
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(
          AppDatabase(
            serversBox: box,
            runsBox: await openRunsBox(secureStore),
            scriptsBox: await openScriptsBox(secureStore),
            monitoringEventsBox: await openMonitoringEventsBox(secureStore),
            peersBox: await openPeersBox(secureStore),
            preferencesBox: await openPreferencesBox(secureStore),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    expect(
      container.read(serverRepositoryProvider),
      isA<HiveServerRepository>(),
    );
  });
}
