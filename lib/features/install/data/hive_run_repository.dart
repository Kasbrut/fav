import 'package:fav/core/persistence/app_database.dart';
import 'package:fav/features/install/data/run_mappers.dart';
import 'package:fav/features/install/domain/install_run.dart';
import 'package:fav/features/install/domain/run_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive_ce.dart';

/// Maximum number of runs kept in the local history (spec §6.4 — last 50).
const int kRunHistoryLimit = 50;

/// [RunRepository] backed by the encrypted Hive database.
class HiveRunRepository implements RunRepository {
  /// Creates a [HiveRunRepository] over the given encrypted box.
  HiveRunRepository(this._box);

  final Box<Map<dynamic, dynamic>> _box;

  @override
  Future<List<InstallRun>> getRecent() async {
    final runs = _box.values.map(runFromMap).toList()
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return runs.take(kRunHistoryLimit).toList();
  }

  @override
  Future<InstallRun?> getById(String runId) async {
    final raw = _box.get(runId);
    return raw == null ? null : runFromMap(raw);
  }

  @override
  Future<List<InstallRun>> getIncomplete() async {
    return _box.values
        .map(runFromMap)
        .where((run) => run.status == RunStatus.running)
        .toList();
  }

  @override
  Future<void> save(InstallRun run) async {
    await _box.put(run.runId, runToMap(run));
    await _pruneHistory();
  }

  @override
  Future<void> delete(String runId) => _box.delete(runId);

  /// Removes the oldest runs once the history exceeds [kRunHistoryLimit].
  Future<void> _pruneHistory() async {
    if (_box.length <= kRunHistoryLimit) {
      return;
    }
    final runs = _box.values.map(runFromMap).toList()
      ..sort((a, b) => a.startedAt.compareTo(b.startedAt));
    final excess = runs.take(_box.length - kRunHistoryLimit);
    for (final run in excess) {
      await _box.delete(run.runId);
    }
  }
}

/// Provides the [RunRepository] backed by the encrypted database.
final Provider<RunRepository> runRepositoryProvider = Provider<RunRepository>(
  (ref) => HiveRunRepository(ref.watch(appDatabaseProvider).runsBox),
);
