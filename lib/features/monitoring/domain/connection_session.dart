import 'package:fav/features/monitoring/domain/peer_event.dart';
import 'package:meta/meta.dart';

/// A pair of connect/disconnect events derived from a stream of [PeerEvent]s.
///
/// Sessions are computed lazily from the events box — they are never
/// persisted. An open session ([end] == null) means the peer was last seen
/// connected and no disconnect has yet been recorded; it should be rendered
/// extending up to "now" on the timeline.
@immutable
class ConnectionSession {
  /// Creates a [ConnectionSession].
  const ConnectionSession({
    required this.peerPublicKey,
    required this.start,
    this.end,
    this.rxBytes = 0,
    this.txBytes = 0,
  });

  /// Peer this session belongs to.
  final String peerPublicKey;

  /// When the session started (server clock).
  final DateTime start;

  /// When the session ended (server clock); `null` while the session is open.
  final DateTime? end;

  /// Cumulative bytes RX delta inside the session, when both endpoints known.
  final int rxBytes;

  /// Cumulative bytes TX delta inside the session, when both endpoints known.
  final int txBytes;

  /// `true` while no disconnect event has been observed yet.
  bool get isOpen => end == null;

  /// Effective duration up to [reference] (typically `now` for open sessions).
  Duration durationUntil(DateTime reference) {
    final close = end ?? reference;
    final diff = close.difference(start);
    return diff.isNegative ? Duration.zero : diff;
  }

  /// Derives the list of sessions from [events] ordered by `serverTimestamp`.
  ///
  /// Algorithm: walk events per-peer in chronological order. A `connect`
  /// opens a session for that peer. The next `disconnect` for the same peer
  /// closes it. Stray disconnects without a prior connect are ignored —
  /// they happen when the retention window cuts off the open side of a
  /// session, or when the agent restarts mid-session.
  ///
  /// `rxBytes` / `txBytes` are computed as the non-negative delta between
  /// the snapshot at end and the snapshot at start; counters can reset on
  /// the server (interface bounce), so a negative delta is clamped to zero.
  static List<ConnectionSession> derive(List<PeerEvent> events) {
    final byPeer = <String, List<PeerEvent>>{};
    for (final event in events) {
      byPeer.putIfAbsent(event.peerPublicKey, () => []).add(event);
    }
    final sessions = <ConnectionSession>[];
    for (final entry in byPeer.entries) {
      final ordered = [...entry.value]
        ..sort((a, b) => a.serverTimestamp.compareTo(b.serverTimestamp));
      PeerEvent? open;
      for (final event in ordered) {
        if (event.type == PeerEventType.connect) {
          // A second `connect` without intervening disconnect means we
          // missed the close event; treat the previous as a single-point
          // session ending at the current connect.
          if (open != null) {
            sessions.add(
              ConnectionSession(
                peerPublicKey: entry.key,
                start: open.serverTimestamp,
                end: event.serverTimestamp,
                rxBytes: _nonNegDelta(open.rx, event.rx),
                txBytes: _nonNegDelta(open.tx, event.tx),
              ),
            );
          }
          open = event;
        } else {
          if (open != null) {
            sessions.add(
              ConnectionSession(
                peerPublicKey: entry.key,
                start: open.serverTimestamp,
                end: event.serverTimestamp,
                rxBytes: _nonNegDelta(open.rx, event.rx),
                txBytes: _nonNegDelta(open.tx, event.tx),
              ),
            );
            open = null;
          }
          // Stray disconnect — ignored.
        }
      }
      if (open != null) {
        sessions.add(
          ConnectionSession(
            peerPublicKey: entry.key,
            start: open.serverTimestamp,
          ),
        );
      }
    }
    sessions.sort((a, b) => a.start.compareTo(b.start));
    return sessions;
  }

  static int _nonNegDelta(int start, int end) {
    final delta = end - start;
    return delta < 0 ? 0 : delta;
  }
}
