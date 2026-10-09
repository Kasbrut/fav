import 'package:fav/features/install/data/hive_run_repository.dart';
import 'package:fav/features/install/domain/install_run.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Local runs still marked running — recovery candidates at app start (§6.4).
///
/// This is a local-only check: verifying the remote state needs the SSH
/// password, which is requested on demand (see `RunRecoveryService`).
final FutureProvider<List<InstallRun>> incompleteRunsProvider =
    FutureProvider<List<InstallRun>>(
      (ref) => ref.watch(runRepositoryProvider).getIncomplete(),
    );
