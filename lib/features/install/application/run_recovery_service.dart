import 'package:fav/core/errors/app_exception.dart';
import 'package:fav/core/utils/app_logger.dart';
import 'package:fav/core/utils/shell_quote.dart';
import 'package:fav/features/install/application/ssh_auth_resolver.dart';
import 'package:fav/features/install/data/hive_run_repository.dart';
import 'package:fav/features/install/data/provisioner/run_state_parser.dart';
import 'package:fav/features/install/data/ssh/dart_ssh_client.dart';
import 'package:fav/features/install/domain/install_run.dart';
import 'package:fav/features/install/domain/run_paths.dart';
import 'package:fav/features/install/domain/run_repository.dart';
import 'package:fav/features/install/domain/ssh_client.dart';
import 'package:fav/features/servers/data/hive_server_repository.dart';
import 'package:fav/features/servers/domain/server_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';
import 'package:meta/meta.dart';

/// Sentinel separating the state file from the exit file in the probe output.
const String _exitSentinel = '---WG-EXIT---';

/// Marker printed when the installer process is still alive.
const String _aliveMarker = 'WG-ALIVE';

/// Outcome of attempting to recover an interrupted run (spec §6.4).
@immutable
sealed class RunRecoveryOutcome {
  /// Const base constructor.
  const RunRecoveryOutcome();
}

/// The run is still in progress; polling can resume on [client].
class RecoveryResumePolling extends RunRecoveryOutcome {
  /// Creates a [RecoveryResumePolling].
  const RecoveryResumePolling({
    required this.client,
    required this.paths,
    this.sudoPassword,
  });

  /// Still-open SSH connection, ready for the polling controller.
  final SshClient client;

  /// Paths of the recovered run.
  final RunPaths paths;

  /// Sudo password the resumed polling must use to read the root-owned
  /// state/exit files (non-root sudoer login); `null` for a root login.
  final String? sudoPassword;
}

/// The run finished while the app was away.
class RecoveryCompleted extends RunRecoveryOutcome {
  /// Creates a [RecoveryCompleted].
  const RecoveryCompleted(this.run);

  /// The run with its final status.
  final InstallRun run;
}

/// The run was lost on the server (reboot or cleanup).
class RecoveryOrphaned extends RunRecoveryOutcome {
  /// Creates a [RecoveryOrphaned].
  const RecoveryOrphaned(this.run);

  /// The run marked [RunStatus.orphaned].
  final InstallRun run;
}

/// Recovery could not be attempted (connection or lookup failure).
class RecoveryFailed extends RunRecoveryOutcome {
  /// Creates a [RecoveryFailed].
  const RecoveryFailed(this.error);

  /// The failure to surface to the user.
  final AppException error;
}

/// Reconnects to a server and reconciles the local record of an interrupted
/// run with the remote state (spec §6.4, §11.2).
class RunRecoveryService {
  /// Creates a [RunRecoveryService].
  RunRecoveryService({
    required this._sshClientFactory,
    required this._serverRepository,
    required this._runRepository,
    required this._authResolver,
    this._stateParser = const RunStateParser(),
    Logger? logger,
  }) : _logger = logger ?? appLogger;

  final SshClient Function() _sshClientFactory;
  final ServerRepository _serverRepository;
  final RunRepository _runRepository;
  final SshAuthResolver _authResolver;
  final RunStateParser _stateParser;
  final Logger _logger;

  /// Recovers [localRun] by reconnecting to the server.
  ///
  /// When the server carries a stored SSH key (hardening was applied)
  /// [password] is ignored and the key is used; otherwise [password] is
  /// required. The password is used only to reconnect and is never
  /// persisted or logged.
  Future<RunRecoveryOutcome> recover({
    required InstallRun localRun,
    String? password,
  }) async {
    _logger.i(
      'Recovery: reconnecting for run ${localRun.runId} '
      '(server ${localRun.serverId})',
    );
    final outcome = await _recover(localRun: localRun, password: password);
    _logger.i('Recovery: run ${localRun.runId} → ${outcome.runtimeType}');
    return outcome;
  }

  Future<RunRecoveryOutcome> _recover({
    required InstallRun localRun,
    String? password,
  }) async {
    final server = await _serverRepository.getById(localRun.serverId);
    if (server == null) {
      return const RecoveryFailed(
        AppException(ErrorCode.runLost, detail: 'unknown server'),
      );
    }
    final SshConnectionParams params;
    try {
      params = await _authResolver.resolve(
        server: server,
        password: password,
      );
    } on AppException catch (error) {
      return RecoveryFailed(error);
    }
    final paths = RunPaths(localRun.runId);
    // The installer (and its state/exit/pid files) is root-owned; a non-root
    // sudoer login must read them under sudo, or a healthy run reads as empty
    // and is wrongly orphaned (audit H4). `null` for a root login (plain cat)
    // or when no password is available (key-auth recovery) — sending an empty
    // password to `sudo -S` would just fail. Matches attachRecovered.
    final sudoPassword =
        server.username != 'root' && (password?.isNotEmpty ?? false)
        ? password
        : null;
    final client = _sshClientFactory();
    var resumeOwnsClient = false;
    try {
      await client.connect(params);
      final outcome = await _reconcile(localRun, client, paths, sudoPassword);
      resumeOwnsClient = outcome is RecoveryResumePolling;
      return outcome;
    } on HostKeyUnknownException {
      // The server's key is no longer trusted (pinned entry lost): fail
      // closed with ERR-HOST-01, consistent with the M5 host-key handling.
      return const RecoveryFailed(AppException(ErrorCode.hostKeyMismatch));
    } on AppException catch (error) {
      // Preserves a real host-key mismatch raised by connect(); this arm
      // must stay before `on Object` so it is never reclassified.
      return RecoveryFailed(error);
    } on Object {
      return const RecoveryFailed(
        AppException(ErrorCode.connHostUnreachable),
      );
    } finally {
      if (!resumeOwnsClient) {
        await client.close();
      }
    }
  }

  Future<RunRecoveryOutcome> _reconcile(
    InstallRun localRun,
    SshClient client,
    RunPaths paths,
    String? sudoPassword,
  ) async {
    final probe = await _runMaybeSudo(
      client,
      "cat '${paths.statePath}' 2>/dev/null; "
      "echo '$_exitSentinel'; "
      "cat '${paths.exitPath}' 2>/dev/null",
      sudoPassword,
    );
    final parts = probe.stdout.split(_exitSentinel);
    final stateRaw = parts.isEmpty ? '' : parts.first;
    final exitRaw = parts.length > 1 ? parts.last.trim() : '';
    final parsed = _stateParser.tryParse(stateRaw);

    if (exitRaw.isNotEmpty) {
      // An installation still needs client.conf/network.env to finalize the
      // local server and tunnel records. Hand the open connection back to the
      // install controller, whose first poll observes the exit immediately
      // and performs the normal secure finalization and cleanup.
      if (localRun.runType == RunType.install) {
        return RecoveryResumePolling(
          client: client,
          paths: paths,
          sudoPassword: sudoPassword,
        );
      }
      final exitCode = int.tryParse(exitRaw) ?? -1;
      final completed = localRun.copyWith(
        status: exitCode == 0 ? RunStatus.success : RunStatus.failed,
        steps: parsed?.steps ?? localRun.steps,
        completedAt: DateTime.now(),
      );
      await _runRepository.save(completed);
      // The run dir holds client.conf (client private key + PSK) and any
      // config.env; it must not linger on the server after the app has the
      // data (spec §10.1). Best-effort — the run already completed.
      try {
        await _runMaybeSudo(
          client,
          "rm -rf '${paths.runDir}'",
          sudoPassword,
        );
      } on Object {
        // Ignore: a cleanup failure must not turn a completed run into a
        // failure. The next recovery/teardown will retry.
      }
      return RecoveryCompleted(completed);
    }

    if (parsed == null) {
      return _orphan(localRun);
    }
    if (!await _isInstallerAlive(client, paths, sudoPassword)) {
      return _orphan(localRun);
    }
    return RecoveryResumePolling(
      client: client,
      paths: paths,
      sudoPassword: sudoPassword,
    );
  }

  Future<RunRecoveryOutcome> _orphan(InstallRun localRun) async {
    final orphaned = localRun.copyWith(
      status: RunStatus.orphaned,
      completedAt: DateTime.now(),
    );
    await _runRepository.save(orphaned);
    return RecoveryOrphaned(orphaned);
  }

  Future<bool> _isInstallerAlive(
    SshClient client,
    RunPaths paths,
    String? sudoPassword,
  ) async {
    // Confirm the pid is alive AND its command line still references this
    // run, so a pid recycled after a server reboot is not mistaken for a
    // live installer. Read the (root-owned) pid file under sudo for a
    // non-root login.
    final result = await _runMaybeSudo(
      client,
      "pid=\$(cat '${paths.pidPath}' 2>/dev/null) && "
      r'kill -0 "$pid" 2>/dev/null && '
      "tr '\\0' ' ' < \"/proc/\$pid/cmdline\" 2>/dev/null "
      "| grep -q '${paths.runId}' && echo '$_aliveMarker'",
      sudoPassword,
    );
    return result.stdout.contains(_aliveMarker);
  }

  /// Runs [command] on [client], elevating with `sudo -S` (password via stdin)
  /// when [sudoPassword] is set — for reading root-owned files as a non-root
  /// login. Runs it plainly when null (root login).
  Future<SshCommandResult> _runMaybeSudo(
    SshClient client,
    String command,
    String? sudoPassword,
  ) {
    if (sudoPassword == null) {
      return client.run(command);
    }
    return client.run(
      "sudo -S -p '' -- sh -c ${shellSingleQuote(command)}",
      stdin: '$sudoPassword\n',
    );
  }
}

/// Provides the [RunRecoveryService].
final Provider<RunRecoveryService> runRecoveryServiceProvider =
    Provider<RunRecoveryService>(
      (ref) => RunRecoveryService(
        sshClientFactory: ref.watch(sshClientFactoryProvider),
        serverRepository: ref.watch(serverRepositoryProvider),
        runRepository: ref.watch(runRepositoryProvider),
        authResolver: ref.watch(sshAuthResolverProvider),
      ),
    );
