import 'dart:async';
import 'dart:math' as math;

import 'package:fav/core/errors/app_exception.dart';
import 'package:fav/core/utils/app_logger.dart';
import 'package:fav/features/monitoring/data/monitor_events_box.dart';
import 'package:fav/features/monitoring/data/ssh_monitor_repository.dart';
import 'package:fav/features/monitoring/domain/client_live_status.dart';
import 'package:fav/features/monitoring/domain/peer_snapshot.dart';
import 'package:fav/features/servers/data/hive_server_repository.dart';
import 'package:fav/features/servers/domain/server.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:meta/meta.dart';

/// Default interval between polls when everything is healthy.
const Duration kMonitorPollInterval = Duration(seconds: 7);

/// Maximum exponential-backoff delay between failed polls.
const Duration kMonitorPollMaxBackoff = Duration(seconds: 30);

/// Number of consecutive poll failures before giving up.
const int kMonitorPollMaxFailures = 20;

/// Snapshot is considered stale when the agent's `generatedAt` is older than
/// this. Distinct status case [ClientLiveStatusUnknownReason.agentStale].
const Duration kMonitorAgentStaleThreshold = Duration(seconds: 90);

/// State exposed by [MonitorPollingController].
@immutable
class MonitorPollingState {
  /// Creates a [MonitorPollingState].
  const MonitorPollingState({
    this.snapshot,
    this.lastError,
    this.lastErrorReason,
    this.consecutiveFailures = 0,
  });

  /// Latest snapshot pulled from the agent, or `null` until one arrives.
  final PeersStateSnapshot? snapshot;

  /// Last error during polling, when any (transient transport / parse).
  final AppException? lastError;

  /// Reason classification for the most recent failure, used to drive the
  /// banner's `Unknown(...)` variants on the UI.
  final ClientLiveStatusUnknownReason? lastErrorReason;

  /// Consecutive failures since the last successful poll.
  final int consecutiveFailures;

  /// Returns a copy with the given fields replaced.
  MonitorPollingState copyWith({
    PeersStateSnapshot? snapshot,
    AppException? lastError,
    ClientLiveStatusUnknownReason? lastErrorReason,
    int? consecutiveFailures,
    bool clearError = false,
  }) {
    return MonitorPollingState(
      snapshot: snapshot ?? this.snapshot,
      lastError: clearError ? null : (lastError ?? this.lastError),
      // `clearError` drops the transient transport error but must still honor
      // an explicitly passed reason (e.g. `notInstalled` on a successful poll
      // whose snapshot file is simply absent) — otherwise the live-status
      // banner misreports a missing agent as `sshDown`.
      lastErrorReason: clearError
          ? lastErrorReason
          : (lastErrorReason ?? this.lastErrorReason),
      consecutiveFailures: consecutiveFailures ?? this.consecutiveFailures,
    );
  }
}

/// Foreground-only poller for the monitor agent (M15-T5). One instance per
/// `serverId`. Auto-disposes when no screen is watching, so polling stops
/// the moment the user leaves a monitoring screen — no background work,
/// no permissions required.
class MonitorPollingController extends Notifier<MonitorPollingState> {
  /// Creates a polling controller for the server identified by [arg].
  MonitorPollingController(this.arg);

  /// The server id this controller is scoped to (family argument).
  final String arg;

  Timer? _timer;
  bool _busy = false;
  bool _disposed = false;
  Duration _currentDelay = kMonitorPollInterval;

  /// High-water mark of consumed events lines, threaded through
  /// [SshMonitorRepository.fetchAll] so each tick downloads only the tail
  /// (audit M13). In-memory only: a fresh controller re-reads the full log
  /// once and the events box dedupes.
  int _eventsLineOffset = 0;
  String? _eventsFileId;

  @override
  MonitorPollingState build() {
    ref.onDispose(_teardown);
    // Defer the first poll to the next event-loop tick so `build()` has
    // already returned before `_pollOnce` calls `state = ...` (which would
    // otherwise fail with "uninitialized provider").
    unawaited(
      Future<void>(() {
        if (!_disposed) {
          unawaited(_pollOnce(arg));
        }
      }),
    );
    _schedule(arg, kMonitorPollInterval);
    return const MonitorPollingState();
  }

  void _teardown() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
  }

  void _schedule(String serverId, Duration delay) {
    if (_disposed) {
      return;
    }
    _timer?.cancel();
    _timer = Timer(delay, () => _pollOnce(serverId));
  }

  Future<void> _pollOnce(String serverId) async {
    if (_disposed || _busy) {
      return;
    }
    _busy = true;
    try {
      final server = await ref.read(serverRepositoryProvider).getById(serverId);
      if (server == null) {
        if (_disposed) {
          return;
        }
        state = state.copyWith(
          lastError: const AppException(
            ErrorCode.monitorPullFailed,
            detail: 'server not found',
          ),
          lastErrorReason: ClientLiveStatusUnknownReason.notInstalled,
          consecutiveFailures: state.consecutiveFailures + 1,
        );
        _scheduleNextAfterFailure(serverId);
        return;
      }
      final result = await _readSnapshot(server);
      if (_disposed) {
        return;
      }
      _eventsLineOffset = result.nextEventsLineOffset;
      _eventsFileId = result.nextEventsFileId;
      if (result.snapshot == null) {
        // The SSH session succeeded but the snapshot file is missing —
        // agent is not installed on this server.
        state = state.copyWith(
          lastErrorReason: ClientLiveStatusUnknownReason.notInstalled,
          consecutiveFailures: 0,
          clearError: true,
        );
      } else {
        state = MonitorPollingState(snapshot: result.snapshot);
        if (result.events.isNotEmpty) {
          final box = ref.read(monitorEventsBoxProvider);
          await box.addAll(result.events);
          await box.prune();
        }
      }
      _currentDelay = kMonitorPollInterval;
      _schedule(serverId, _currentDelay);
    } on AppException catch (error) {
      if (_disposed) {
        return;
      }
      state = state.copyWith(
        lastError: error,
        lastErrorReason: ClientLiveStatusUnknownReason.sshDown,
        consecutiveFailures: state.consecutiveFailures + 1,
      );
      _scheduleNextAfterFailure(serverId);
    } on Object catch (error) {
      // M15-T10 (security audit): log type-only — remote stderr may flow
      // through these errors.
      appLogger.w('Monitor poll failed: ${error.runtimeType}');
      if (_disposed) {
        return;
      }
      state = state.copyWith(
        lastError: AppException(
          ErrorCode.monitorPullFailed,
          detail: 'monitor poll: ${error.runtimeType}',
        ),
        lastErrorReason: ClientLiveStatusUnknownReason.sshDown,
        consecutiveFailures: state.consecutiveFailures + 1,
      );
      _scheduleNextAfterFailure(serverId);
    } finally {
      _busy = false;
    }
  }

  Future<MonitorReadResult> _readSnapshot(Server server) async {
    final repository = ref.read(monitorRepositoryProvider);
    // The SSH-backed implementation does both in one round trip; if a
    // future implementation does not implement it, fall back to the iface.
    if (repository is SshMonitorRepository) {
      return repository.fetchAll(
        server,
        eventsLineOffset: _eventsLineOffset,
        eventsFileId: _eventsFileId,
      );
    }
    final snapshot = await repository.fetchSnapshot(server);
    final events = await repository.fetchEvents(server);
    return MonitorReadResult(snapshot: snapshot, events: events);
  }

  void _scheduleNextAfterFailure(String serverId) {
    if (state.consecutiveFailures >= kMonitorPollMaxFailures) {
      // Give up until the screen is re-opened. Auto-dispose handles the
      // teardown when the user navigates away.
      _timer?.cancel();
      return;
    }
    final exp = math.pow(2, math.min(state.consecutiveFailures, 6)).toInt();
    _currentDelay = Duration(
      milliseconds: math.min(
        kMonitorPollMaxBackoff.inMilliseconds,
        kMonitorPollInterval.inMilliseconds * exp,
      ),
    );
    _schedule(serverId, _currentDelay);
  }
}

/// Provides the monitoring polling state per server id.
final NotifierProviderFamily<
  MonitorPollingController,
  MonitorPollingState,
  String
>
monitorPollingControllerProvider = NotifierProvider.autoDispose
    .family<MonitorPollingController, MonitorPollingState, String>(
      MonitorPollingController.new,
    );
