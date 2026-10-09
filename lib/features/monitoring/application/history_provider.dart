import 'package:fav/features/monitoring/application/monitor_polling_controller.dart';
import 'package:fav/features/monitoring/data/monitor_events_box.dart';
import 'package:fav/features/monitoring/domain/connection_session.dart';
import 'package:fav/features/monitoring/domain/peer_event.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:meta/meta.dart';

/// Time-window options exposed by the history screen.
enum HistoryRange {
  /// Last 24 hours.
  last24h,

  /// Last 7 days (matches the agent retention).
  last7d,
}

/// Returns the [Duration] covered by a [HistoryRange].
extension HistoryRangeDuration on HistoryRange {
  /// Window width.
  Duration get duration => switch (this) {
    HistoryRange.last24h => const Duration(hours: 24),
    HistoryRange.last7d => const Duration(days: 7),
  };
}

/// Filter state applied client-side on top of the per-server event stream.
@immutable
class HistoryFilter {
  /// Creates a [HistoryFilter].
  const HistoryFilter({
    this.range = HistoryRange.last24h,
    this.peerPublicKey,
    this.eventTypes = const {PeerEventType.connect, PeerEventType.disconnect},
  });

  /// Selected window.
  final HistoryRange range;

  /// When `null`, all peers are shown.
  final String? peerPublicKey;

  /// Event-type filter for the log; the chart always shows full sessions.
  final Set<PeerEventType> eventTypes;

  /// Returns a copy with the given fields replaced.
  HistoryFilter copyWith({
    HistoryRange? range,
    Object? peerPublicKey = _unset,
    Set<PeerEventType>? eventTypes,
  }) {
    return HistoryFilter(
      range: range ?? this.range,
      peerPublicKey: identical(peerPublicKey, _unset)
          ? this.peerPublicKey
          : peerPublicKey as String?,
      eventTypes: eventTypes ?? this.eventTypes,
    );
  }

  static const Object _unset = Object();
}

/// Notifier-backed filter state, one instance per server.
class HistoryFilterController extends Notifier<HistoryFilter> {
  /// Creates a filter controller for the server identified by [arg].
  HistoryFilterController(this.arg);

  /// The server id this controller is scoped to (family argument).
  final String arg;

  @override
  HistoryFilter build() => const HistoryFilter();

  /// Updates the time window.
  void setRange(HistoryRange range) {
    state = state.copyWith(range: range);
  }

  /// Sets the peer filter; pass `null` for "all peers".
  void setPeer(String? peerPublicKey) {
    state = state.copyWith(peerPublicKey: peerPublicKey);
  }

  /// Toggles a [PeerEventType] in/out of the filter set. The chart still
  /// renders both — only the log table observes this set.
  ///
  /// The last selected type cannot be removed: an empty set would show an
  /// empty log with no way back, so the final chip stays locked on.
  void toggleEventType(PeerEventType type) {
    final next = {...state.eventTypes};
    if (next.contains(type)) {
      if (next.length == 1) return;
      next.remove(type);
    } else {
      next.add(type);
    }
    state = state.copyWith(eventTypes: next);
  }
}

/// Per-server filter state. Auto-dispose: the next entry on the screen
/// starts from the defaults.
final NotifierProviderFamily<HistoryFilterController, HistoryFilter, String>
historyFilterProvider = NotifierProvider.autoDispose
    .family<HistoryFilterController, HistoryFilter, String>(
      HistoryFilterController.new,
    );

/// Aggregated result rendered by the history screen.
@immutable
class ServerHistory {
  /// Creates a [ServerHistory].
  const ServerHistory({
    required this.windowStart,
    required this.windowEnd,
    required this.peers,
    required this.sessions,
    required this.filteredEvents,
  });

  /// Inclusive start of the visible window.
  final DateTime windowStart;

  /// Exclusive end of the visible window (typically `now`).
  final DateTime windowEnd;

  /// Distinct peers seen anywhere in the unfiltered history — used to
  /// populate the peer dropdown.
  final List<String> peers;

  /// Sessions clipped to the visible window. Open sessions extend to
  /// [windowEnd]; sessions that started before [windowStart] are clipped
  /// at the left edge.
  final List<ConnectionSession> sessions;

  /// Events matching the active filter, ordered by `serverTimestamp` desc.
  final List<PeerEvent> filteredEvents;
}

/// Raw events for a server, refreshed whenever the polling controller
/// updates its state (which it does after each box write).
///
/// Using the polling state as the dependency is intentional: the events box
/// does not expose a stream wrapper, and the polling controller is the only
/// writer — when it ticks, history must refresh.
final ProviderFamily<List<PeerEvent>, String> peerEventsProvider = Provider
    .autoDispose
    .family<List<PeerEvent>, String>((ref, serverId) {
      ref.watch(monitorPollingControllerProvider(serverId));
      return ref.watch(monitorEventsBoxProvider).getForServer(serverId);
    });

/// Derives the filtered, windowed view used by the UI.
final ProviderFamily<ServerHistory, String> serverHistoryProvider = Provider
    .autoDispose
    .family<ServerHistory, String>((ref, serverId) {
      final events = ref.watch(peerEventsProvider(serverId));
      final filter = ref.watch(historyFilterProvider(serverId));
      final now = DateTime.now().toUtc();
      final windowStart = now.subtract(filter.range.duration);

      final peers = <String>{for (final e in events) e.peerPublicKey}.toList()
        ..sort();

      final allSessions = ConnectionSession.derive(events);
      final clippedSessions = <ConnectionSession>[];
      for (final session in allSessions) {
        if (filter.peerPublicKey != null &&
            session.peerPublicKey != filter.peerPublicKey) {
          continue;
        }
        final effectiveEnd = session.end ?? now;
        if (effectiveEnd.isBefore(windowStart)) {
          continue;
        }
        if (session.start.isAfter(now)) {
          continue;
        }
        final clippedStart = session.start.isBefore(windowStart)
            ? windowStart
            : session.start;
        clippedSessions.add(
          ConnectionSession(
            peerPublicKey: session.peerPublicKey,
            start: clippedStart,
            end: session.end,
            rxBytes: session.rxBytes,
            txBytes: session.txBytes,
          ),
        );
      }

      final filteredEvents =
          events.where((event) {
              if (filter.peerPublicKey != null &&
                  event.peerPublicKey != filter.peerPublicKey) {
                return false;
              }
              if (!filter.eventTypes.contains(event.type)) {
                return false;
              }
              if (event.serverTimestamp.isBefore(windowStart)) {
                return false;
              }
              return true;
            }).toList()
            ..sort((a, b) => b.serverTimestamp.compareTo(a.serverTimestamp));

      return ServerHistory(
        windowStart: windowStart,
        windowEnd: now,
        peers: peers,
        sessions: clippedSessions,
        filteredEvents: filteredEvents,
      );
    });
