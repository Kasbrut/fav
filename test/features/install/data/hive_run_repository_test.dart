import 'dart:io';

import 'package:fav/core/persistence/app_database.dart';
import 'package:fav/features/install/data/hive_run_repository.dart';
import 'package:fav/features/install/domain/install_run.dart';
import 'package:fav/features/settings/data/preferences_box.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';

import '../../../support/in_memory_secure_store.dart';

void main() {
  late Directory tempDir;
  late InMemorySecureStore secureStore;
  late HiveRunRepository repository;

  InstallRun buildRun(
    String id, {
    RunStatus status = RunStatus.running,
    DateTime? startedAt,
  }) {
    return InstallRun(
      runId: id,
      serverId: 'srv-1',
      status: status,
      steps: const [],
      scriptWasModified: false,
      startedAt: startedAt ?? DateTime(2026, 5, 18),
    );
  }

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('wg_run_repo_test');
    Hive.init(tempDir.path);
    secureStore = InMemorySecureStore();
    repository = HiveRunRepository(await openRunsBox(secureStore));
  });

  tearDown(() async {
    await Hive.close();
    tempDir.deleteSync(recursive: true);
  });

  test('saves and reads a run by id', () async {
    await repository.save(buildRun('run-1'));
    expect((await repository.getById('run-1'))?.runId, 'run-1');
    expect(await repository.getById('missing'), isNull);
  });

  test('getRecent returns runs newest first', () async {
    await repository.save(buildRun('old', startedAt: DateTime(2026)));
    await repository.save(buildRun('new', startedAt: DateTime(2026, 5)));
    final recent = await repository.getRecent();
    expect(recent.map((run) => run.runId), ['new', 'old']);
  });

  test('getIncomplete returns only running runs', () async {
    await repository.save(buildRun('a'));
    await repository.save(buildRun('b', status: RunStatus.success));
    await repository.save(buildRun('c'));
    final incomplete = await repository.getIncomplete();
    expect(incomplete.map((run) => run.runId).toSet(), {'a', 'c'});
  });

  test('save prunes the history to the newest runs', () async {
    for (var i = 0; i < kRunHistoryLimit + 5; i++) {
      await repository.save(
        buildRun(
          'run-$i',
          status: RunStatus.success,
          startedAt: DateTime(2026).add(Duration(days: i)),
        ),
      );
    }
    final all = await repository.getRecent();
    expect(all, hasLength(kRunHistoryLimit));
    expect(all.first.runId, 'run-${kRunHistoryLimit + 4}');
    expect(await repository.getById('run-0'), isNull);
  });

  test('delete removes a run', () async {
    await repository.save(buildRun('run-1'));
    await repository.delete('run-1');
    expect(await repository.getById('run-1'), isNull);
  });

  test('runRepositoryProvider yields a HiveRunRepository', () async {
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(
          AppDatabase(
            serversBox: await openServersBox(secureStore),
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
    expect(container.read(runRepositoryProvider), isA<HiveRunRepository>());
  });
}
