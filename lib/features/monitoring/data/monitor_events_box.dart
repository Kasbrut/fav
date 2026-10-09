import 'dart:async';

import 'package:fav/core/persistence/app_database.dart';
import 'package:fav/features/monitoring/domain/peer_event.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive_ce.dart';

/// Retention window for monitoring events (M15-T4) — 7 days.
const Duration kMonitorEventsRetention = Duration(days: 7);

/// Minimum spacing between prune passes (M15-T5). Per-tick prune would be a
/// linear scan of the box; once a polling tick is plenty.
const Duration kMonitorEventsPruneCooldown = Duration(seconds: 30);

/// Wraps the encrypted `monitoring_events` Hive box. Composite-keyed on
/// `(serverId, peerPublicKey, serverTimestamp)` so the future multi-client
/// UI does not need a box rewrite.
class MonitorEventsBox {
  /// Creates a [MonitorEventsBox] over the given open box.
  MonitorEventsBox(this._box);

  final Box<Map<dynamic, dynamic>> _box;
  DateTime _lastPruneAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// Appends each event in [events]. Duplicates by composite key are
  /// overwritten (idempotent).
  Future<void> addAll(Iterable<PeerEvent> events) async {
    final batch = <String, Map<String, Object>>{};
    for (final event in events) {
      batch[event.storageKey] = event.toMap();
    }
    if (batch.isEmpty) {
      return;
    }
    await _box.putAll(batch);
  }

  /// Returns every event for [serverId], ordered by `serverTimestamp`
  /// ascending. Rows that fail to map are skipped.
  List<PeerEvent> getForServer(String serverId) {
    final events = <PeerEvent>[];
    for (final value in _box.values) {
      final event = PeerEvent.fromMap(value);
      if (event == null || event.serverId != serverId) {
        continue;
      }
      events.add(event);
    }
    events.sort((a, b) => a.serverTimestamp.compareTo(b.serverTimestamp));
    return events;
  }

  /// Removes events older than `now - retention`, basing the cutoff on the
  /// **server** timestamp carried in each event — not the device clock —
  /// so a clock jump on the phone cannot over-prune (M15 design constraint).
  ///
  /// Rate-limited: returns immediately when the last prune ran within
  /// [kMonitorEventsPruneCooldown]. Pass [force] = true to bypass the
  /// cooldown (e.g. on box open).
  Future<int> prune({
    Duration retention = kMonitorEventsRetention,
    DateTime? now,
    bool force = false,
  }) async {
    final wall = now ?? DateTime.now().toUtc();
    if (!force && wall.difference(_lastPruneAt) < kMonitorEventsPruneCooldown) {
      return 0;
    }
    _lastPruneAt = wall;
    // M15-T10 (security audit): the cutoff must be derived from the
    // server-clock anchor — the newest serverTimestamp in the box — so a
    // device clock jumping forward cannot over-prune real history. When
    // the box is empty (first run), there is nothing to prune anyway.
    final events = <PeerEvent>[];
    final unrecoverable = <dynamic>[];
    for (final key in _box.keys) {
      final value = _box.get(key);
      if (value == null) {
        continue;
      }
      final event = PeerEvent.fromMap(value);
      if (event == null) {
        unrecoverable.add(key);
        continue;
      }
      events.add(event);
    }
    if (events.isEmpty) {
      if (unrecoverable.isNotEmpty) {
        await _box.deleteAll(unrecoverable);
        return unrecoverable.length;
      }
      return 0;
    }
    final anchor = events
        .map((event) => event.serverTimestamp)
        .reduce((a, b) => a.isAfter(b) ? a : b);
    final cutoff = anchor.subtract(retention);
    final stale = <dynamic>[...unrecoverable];
    for (final event in events) {
      if (event.serverTimestamp.isBefore(cutoff)) {
        stale.add(event.storageKey);
      }
    }
    if (stale.isEmpty) {
      return 0;
    }
    await _box.deleteAll(stale);
    return stale.length;
  }
}

/// Provides the [MonitorEventsBox] over the opened monitoring-events box,
/// running an initial prune as soon as the provider is first read.
final Provider<MonitorEventsBox> monitorEventsBoxProvider =
    Provider<MonitorEventsBox>((ref) {
      final box = MonitorEventsBox(
        ref.watch(appDatabaseProvider).monitoringEventsBox,
      );
      // Prune-on-open (M15-T4): bypass the cooldown the first time the box
      // is materialized this session. Fire-and-forget — failures here must
      // never block monitoring screens from rendering.
      unawaited(box.prune(force: true));
      return box;
    });
