import 'dart:io';

import 'package:fav/features/monitoring/data/monitor_events_box.dart';
import 'package:fav/features/monitoring/domain/peer_event.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';

PeerEvent _event({
  required DateTime serverTimestamp,
  String serverId = 'srv-1',
  String peerPublicKey = 'peer1',
  PeerEventType type = PeerEventType.connect,
  int rx = 0,
  int tx = 0,
}) {
  return PeerEvent(
    serverId: serverId,
    peerPublicKey: peerPublicKey,
    type: type,
    serverTimestamp: serverTimestamp,
    rx: rx,
    tx: tx,
    latestHandshake: 0,
  );
}

void main() {
  late Directory tempDir;
  late Box<Map<dynamic, dynamic>> rawBox;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('wg_mon_box');
    Hive.init(tempDir.path);
    rawBox = await Hive.openBox<Map<dynamic, dynamic>>('monitoring_events');
  });

  tearDown(() async {
    await Hive.close();
    tempDir.deleteSync(recursive: true);
  });

  test('addAll persists events keyed by composite storageKey', () async {
    final box = MonitorEventsBox(rawBox);
    final ts = DateTime.utc(2026, 5, 22, 9);
    await box.addAll([_event(serverTimestamp: ts)]);
    expect(rawBox.values, hasLength(1));
    // Same event again — overwritten in place, not duplicated.
    await box.addAll([_event(serverTimestamp: ts, rx: 99)]);
    expect(rawBox.values, hasLength(1));
    expect(box.getForServer('srv-1').single.rx, 99);
  });

  test(
    'getForServer returns events for the right server, sorted by ts',
    () async {
      final box = MonitorEventsBox(rawBox);
      await box.addAll([
        _event(serverTimestamp: DateTime.utc(2026, 5, 22, 10)),
        _event(serverTimestamp: DateTime.utc(2026, 5, 22, 8)),
        _event(
          serverId: 'other',
          serverTimestamp: DateTime.utc(2026, 5, 22, 9),
        ),
      ]);
      final events = box.getForServer('srv-1');
      expect(events, hasLength(2));
      expect(events.first.serverTimestamp, DateTime.utc(2026, 5, 22, 8));
      expect(events.last.serverTimestamp, DateTime.utc(2026, 5, 22, 10));
    },
  );

  test('prune drops events older than 7 days from serverTimestamp', () async {
    final box = MonitorEventsBox(rawBox);
    final now = DateTime.utc(2026, 5, 22);
    await box.addAll([
      _event(serverTimestamp: now.subtract(const Duration(days: 8))),
      _event(serverTimestamp: now.subtract(const Duration(days: 6))),
      _event(serverTimestamp: now),
    ]);
    final removed = await box.prune(force: true, now: now);
    expect(removed, 1);
    final remaining = box.getForServer('srv-1');
    expect(remaining, hasLength(2));
    expect(
      remaining.first.serverTimestamp,
      now.subtract(const Duration(days: 6)),
    );
  });

  test('prune is rate-limited unless force=true', () async {
    final box = MonitorEventsBox(rawBox);
    final now = DateTime.utc(2026, 5, 22);
    // Seed two events: a fresh anchor (so the cutoff is computed against it)
    // and a stale entry 8 days behind it. M15-T10 security fix: prune
    // derives the cutoff from the newest serverTimestamp in the box.
    await box.addAll([
      _event(serverTimestamp: now),
      _event(
        peerPublicKey: 'peer-stale',
        serverTimestamp: now.subtract(const Duration(days: 8)),
      ),
    ]);
    final first = await box.prune(force: true, now: now);
    expect(first, 1);
    // Subsequent prune within the cooldown is a no-op even when stale data
    // appears.
    await box.addAll([
      _event(
        peerPublicKey: 'peer2',
        serverTimestamp: now.subtract(const Duration(days: 9)),
      ),
    ]);
    final cooled = await box.prune(now: now);
    expect(cooled, 0);
    // With force=true the prune runs again.
    final forced = await box.prune(force: true, now: now);
    expect(forced, 1);
  });
}
