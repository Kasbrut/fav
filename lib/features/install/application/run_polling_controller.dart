import 'dart:async';

import 'package:fav/core/errors/app_exception.dart';
import 'package:fav/core/utils/app_logger.dart';
import 'package:fav/core/utils/shell_quote.dart';
import 'package:fav/features/install/data/hive_run_repository.dart';
import 'package:fav/features/install/data/provisioner/run_state_parser.dart';
import 'package:fav/features/install/domain/install_run.dart';
import 'package:fav/features/install/domain/install_step.dart';
import 'package:fav/features/install/domain/run_paths.dart';
import 'package:fav/features/install/domain/ssh_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';
import 'package:meta/meta.dart';

/// Sentinel separating the state file from the exit file in a poll's output.
const String _exitSentinel = '---WG-EXIT---';

/// Default interval between successful state polls (spec §7.5).
const Duration _defaultPollInterval = Duration(milliseconds: 2500);

/// Default maximum delay between failed poll attempts (spec §7.5).
const Duration _defaultMaxBackoff = Duration(seconds: 30);

/// Default number of failed attempts tolerated before giving up (spec §7.5).
const int _defaultMaxFailures = 20;

/// Default ceiling on a single poll read. A silent network black-hole (Wi-Fi ↔
/// cellular switch, NAT drop) can leave a stdin-less `run` awaiting forever; a
/// timeout here turns that into a counted failure so the backoff budget still
/// ends the loop with [ErrorCode.pollingTimeout] (audit H5).
const Duration _defaultPollReadTimeout = Duration(seconds: 60);

/// UI-facing state of a polled installation run.
@immutable
class RunPollingState {
  /// Creates a [RunPollingState].
  const RunPollingState({
    this.run,
    this.warnings = const [],
    this.connectionLost = false,
    this.isTerminal = false,
    this.error,
  });

  /// The run being polled; `null` before polling starts.
  final InstallRun? run;

  /// Non-fatal warnings reported by the installer.
  final List<String> warnings;

  /// Whether the last poll failed and polling is backing off.
  final bool connectionLost;

  /// Whether polling has stopped (the run ended or timed out).
  final bool isTerminal;

  /// Failure that ended polling, if any.
  final AppException? error;

  /// Returns a copy of this state with the given fields replaced.
  ///
  /// TRAP: `run` and `error` cannot be CLEARED through this method —
  /// passing null keeps the old value. Construct a new [RunPollingState]
  /// to drop one (deep-audit low nit).
  RunPollingState copyWith({
    InstallRun? run,
    List<String>? warnings,
    bool? connectionLost,
    bool? isTerminal,
    AppException? error,
  }) {
    return RunPollingState(
      run: run ?? this.run,
      warnings: warnings ?? this.warnings,
      connectionLost: connectionLost ?? this.connectionLost,
      isTerminal: isTerminal ?? this.isTerminal,
      error: error ?? this.error,
    );
  }
}

/// Polls a run's state file on the server and exposes its progress (§7.5).
///
/// The connection is reused for the whole polling session; a transient error
/// triggers exponential backoff, and after enough consecutive failures
/// polling stops with [ErrorCode.pollingTimeout].
class RunPollingController extends Notifier<RunPollingState> {
  static const RunStateParser _parser = RunStateParser();

  Logger get _logger => ref.read(loggerProvider);

  SshClient? _client;
  late InstallRun _run;
  bool _stopped = false;
  bool _started = false;

  /// Last logged step snapshot; polling repeats every ~2.5 s, so progress is
  /// only logged when it actually changes.
  String _lastLoggedSteps = '';

  /// Sudo password when the SSH login is a non-root sudoer: the state/exit
  /// files are written by the root installer, so reading them needs `sudo`.
  /// Null for a root login (plain `cat`).
  String? _sudoPassword;

  @override
  RunPollingState build() {
    ref.onDispose(_teardown);
    return const RunPollingState();
  }

  /// Starts polling the run identified by [paths] over the connected [client].
  ///
  /// [client] is borrowed: the controller closes it when polling stops.
  Future<void> start({
    required SshClient client,
    required InstallRun run,
    required RunPaths paths,
    Future<SshClient> Function()? reconnect,
    String? sudoPassword,
    Duration pollInterval = _defaultPollInterval,
    Duration maxBackoff = _defaultMaxBackoff,
    int maxConsecutiveFailures = _defaultMaxFailures,
    Duration pollReadTimeout = _defaultPollReadTimeout,
  }) async {
    if (_started) {
      // Refused: this controller instance already owns a session. The
      // borrowed [client] was handed over by the caller — close it instead
      // of leaking the connection (audit M2).
      unawaited(client.close());
      return;
    }
    _started = true;
    _client = client;
    _sudoPassword = sudoPassword;
    _run = run;
    state = RunPollingState(run: run);
    await _save(run);
    await _pollLoop(
      client: client,
      paths: paths,
      reconnect: reconnect,
      pollInterval: pollInterval,
      maxBackoff: maxBackoff,
      maxConsecutiveFailures: maxConsecutiveFailures,
      pollReadTimeout: pollReadTimeout,
    );
  }

  /// Stops polling and releases the SSH connection.
  void stop() => _teardown();

  Future<void> _pollLoop({
    required SshClient client,
    required RunPaths paths,
    required Future<SshClient> Function()? reconnect,
    required Duration pollInterval,
    required Duration maxBackoff,
    required int maxConsecutiveFailures,
    required Duration pollReadTimeout,
  }) async {
    var failures = 0;
    var activeClient = client;
    while (!_stopped) {
      _PollOutput output;
      try {
        // Bound each read: a black-holed connection would otherwise leave the
        // await pending forever (no error to trigger the backoff budget). A
        // TimeoutException is caught below and counted as a failure (H5).
        output = await _pollOnce(activeClient, paths).timeout(pollReadTimeout);
      } on Object catch (error) {
        if (_stopped) return;
        failures++;
        _logger.w(
          'Poll ${_run.runId} failed '
          '($failures/$maxConsecutiveFailures): ${error.runtimeType}',
        );
        if (failures >= maxConsecutiveFailures) {
          _logger.w(
            'Poll ${_run.runId}: giving up after $failures '
            'consecutive failures',
          );
          _finishWithTimeout();
          return;
        }
        if (_stopped) {
          return;
        }
        state = state.copyWith(connectionLost: true);
        if (reconnect != null) {
          await activeClient.close();
          try {
            activeClient = await reconnect();
            _client = activeClient;
          } on Object catch (reconnectError) {
            _logger.w(
              'Poll ${_run.runId}: reconnect failed '
              '(${reconnectError.runtimeType})',
            );
          }
        }
        await Future<void>.delayed(
          _backoff(failures, pollInterval, maxBackoff),
        );
        continue;
      }
      failures = 0;
      if (_stopped) {
        return;
      }
      await _applyOutput(output);
      if (state.isTerminal) {
        _teardown();
        return;
      }
      await Future<void>.delayed(pollInterval);
    }
  }

  Future<_PollOutput> _pollOnce(SshClient client, RunPaths paths) async {
    final read =
        "cat '${paths.statePath}' 2>/dev/null; "
        "echo '$_exitSentinel'; "
        "cat '${paths.exitPath}' 2>/dev/null";
    final sudoPassword = _sudoPassword;
    // For a non-root login the installer (and thus its state/exit files) is
    // root-owned, so read them under sudo (password via stdin). For root, a
    // plain read.
    final result = sudoPassword == null
        ? await client.run(read)
        : await client.run(
            "sudo -S -p '' -- sh -c ${shellSingleQuote(read)}",
            stdin: '$sudoPassword\n',
          );
    final parts = result.stdout.split(_exitSentinel);
    if (parts.length != 2 ||
        (parts.last.trim().isEmpty && _parser.tryParse(parts.first) == null)) {
      // Missing files, invalid state or failed sudo must consume the retry
      // budget. Treating empty output as progress would poll forever.
      throw const FormatException('installer state is unavailable');
    }
    return _PollOutput(
      stateRaw: parts.isEmpty ? '' : parts.first,
      exitRaw: parts.length > 1 ? parts.last.trim() : '',
    );
  }

  Future<void> _applyOutput(_PollOutput output) async {
    final parsed = _parser.tryParse(output.stateRaw);
    if (output.exitRaw.isNotEmpty) {
      await _finishWithExit(output.exitRaw, parsed);
      return;
    }
    if (parsed == null) {
      // Soft miss: the file was caught mid-write; keep the previous state.
      if (state.connectionLost) {
        state = state.copyWith(connectionLost: false);
      }
      return;
    }
    final updated = _run.copyWith(status: parsed.status, steps: parsed.steps);
    _run = updated;
    _logStepsIfChanged(parsed);
    state = RunPollingState(run: updated, warnings: parsed.warnings);
    await _save(updated);
  }

  void _logStepsIfChanged(ParsedRunState parsed) {
    final snapshot = parsed.steps
        .map((step) => '${step.key}=${step.status.name}')
        .join(' ');
    if (snapshot == _lastLoggedSteps) return;
    _lastLoggedSteps = snapshot;
    _logger.d('Poll ${_run.runId}: $snapshot');
  }

  Future<void> _finishWithExit(String exitRaw, ParsedRunState? parsed) async {
    final exitCode = int.tryParse(exitRaw) ?? -1;
    final steps = parsed?.steps ?? _run.steps;
    final finalRun = _run.copyWith(
      status: exitCode == 0 ? RunStatus.success : RunStatus.failed,
      steps: steps,
      completedAt: DateTime.now(),
    );
    _run = finalRun;
    _logger.i(
      'Poll ${_run.runId} finished: exit $exitCode '
      '(${finalRun.status.name})',
    );
    final error = exitCode == 0
        ? null
        : AppException(
            ErrorCode.runStepFailed,
            detail: parsed?.errorMessage ?? _failedStepKey(steps),
          );
    state = RunPollingState(
      run: finalRun,
      warnings: parsed?.warnings ?? state.warnings,
      isTerminal: true,
      error: error,
    );
    await _save(finalRun);
  }

  void _finishWithTimeout() {
    state = state.copyWith(
      connectionLost: true,
      isTerminal: true,
      error: const AppException(ErrorCode.pollingTimeout),
    );
    _teardown();
  }

  Duration _backoff(int failures, Duration base, Duration max) {
    final scaled = base * (1 << (failures - 1));
    return scaled > max ? max : scaled;
  }

  String _failedStepKey(List<InstallStep> steps) {
    for (final step in steps) {
      if (step.status == StepStatus.error) {
        return step.key;
      }
    }
    return 'unknown';
  }

  Future<void> _save(InstallRun run) {
    return ref.read(runRepositoryProvider).save(run);
  }

  void _teardown() {
    _stopped = true;
    _sudoPassword = null;
    unawaited(_client?.close());
    _client = null;
  }
}

/// Holds one poll's split output: the state file and the exit file contents.
@immutable
class _PollOutput {
  const _PollOutput({required this.stateRaw, required this.exitRaw});

  final String stateRaw;
  final String exitRaw;
}

/// Controls polling of a single installation run.
final NotifierProvider<RunPollingController, RunPollingState>
runPollingControllerProvider =
    NotifierProvider.autoDispose<RunPollingController, RunPollingState>(
      RunPollingController.new,
    );
