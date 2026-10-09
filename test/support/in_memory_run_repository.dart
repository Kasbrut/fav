import 'package:fav/features/install/domain/install_run.dart';
import 'package:fav/features/install/domain/run_repository.dart';

/// In-memory [RunRepository] for tests.
class InMemoryRunRepository implements RunRepository {
  /// Stored runs, exposed directly so tests can assert on them.
  final List<InstallRun> runs = [];

  @override
  Future<List<InstallRun>> getRecent() async {
    return [...runs]..sort((a, b) => b.startedAt.compareTo(a.startedAt));
  }

  @override
  Future<InstallRun?> getById(String runId) async {
    final matches = runs.where((run) => run.runId == runId);
    return matches.isEmpty ? null : matches.first;
  }

  @override
  Future<List<InstallRun>> getIncomplete() async {
    return runs.where((run) => run.status == RunStatus.running).toList();
  }

  @override
  Future<void> save(InstallRun run) async {
    runs
      ..removeWhere((existing) => existing.runId == run.runId)
      ..add(run);
  }

  @override
  Future<void> delete(String runId) async {
    runs.removeWhere((run) => run.runId == runId);
  }
}
