import 'package:fav/features/install/domain/install_run.dart';

/// Stores the local history of installation runs (spec §6.4, RF-12).
abstract interface class RunRepository {
  /// Returns the most recent runs, newest first, capped at the history limit.
  Future<List<InstallRun>> getRecent();

  /// Returns the run with [runId], or `null` when it is unknown.
  Future<InstallRun?> getById(String runId);

  /// Returns the runs still in [RunStatus.running] — recovery candidates.
  Future<List<InstallRun>> getIncomplete();

  /// Inserts or updates [run], pruning the history to the newest runs.
  Future<void> save(InstallRun run);

  /// Removes the run with [runId].
  Future<void> delete(String runId);
}
