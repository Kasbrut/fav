import 'package:fav/features/monitoring/application/history_provider.dart';
import 'package:fav/features/monitoring/domain/peer_event.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

PeerEvent _ev(
  String peer,
  PeerEventType type,
  DateTime ts, {
  int rx = 0,
  int tx = 0,
}) => PeerEvent(
  serverId: 'srv',
  peerPublicKey: peer,
  type: type,
  serverTimestamp: ts,
  rx: rx,
  tx: tx,
  latestHandshake: 0,
);

void main() {
  group('HistoryFilter.copyWith', () {
    test('explicit null clears peerPublicKey', () {
      const filter = HistoryFilter(peerPublicKey: 'p1');
      final cleared = filter.copyWith(peerPublicKey: null);
      expect(cleared.peerPublicKey, isNull);
    });

    test('omitted parameter keeps previous peerPublicKey', () {
      const filter = HistoryFilter(peerPublicKey: 'p1');
      final next = filter.copyWith(range: HistoryRange.last7d);
      expect(next.peerPublicKey, 'p1');
      expect(next.range, HistoryRange.last7d);
    });
  });

  group('HistoryFilterController', () {
    test('toggleEventType removes and re-adds a type', () {
      final container = ProviderContainer()
        ..listen(historyFilterProvider('srv'), (_, _) {});
      addTearDown(container.dispose);
      final controller = container.read(historyFilterProvider('srv').notifier)
        ..toggleEventType(PeerEventType.connect);
      expect(
        container.read(historyFilterProvider('srv')).eventTypes,
        {PeerEventType.disconnect},
      );
      controller.toggleEventType(PeerEventType.connect);
      expect(
        container.read(historyFilterProvider('srv')).eventTypes,
        containsAll([PeerEventType.connect, PeerEventType.disconnect]),
      );
    });

    test('toggleEventType keeps the last selected type (no dead end)', () {
      final container = ProviderContainer()
        ..listen(historyFilterProvider('srv'), (_, _) {});
      addTearDown(container.dispose);
      container.read(historyFilterProvider('srv').notifier)
        // -> {disconnect}, then removing the only remaining type is ignored.
        ..toggleEventType(PeerEventType.connect)
        ..toggleEventType(PeerEventType.disconnect);
      expect(container.read(historyFilterProvider('srv')).eventTypes, {
        PeerEventType.disconnect,
      });
    });
  });

  group('serverHistoryProvider', () {
    test('filters by event type and peer and clips to the window', () {
      final now = DateTime.now().toUtc();
      final inWindow = now.subtract(const Duration(hours: 1));
      final out24h = now.subtract(const Duration(hours: 30));
      final events = <PeerEvent>[
        _ev('p1', PeerEventType.connect, inWindow),
        _ev(
          'p1',
          PeerEventType.disconnect,
          inWindow.add(const Duration(minutes: 10)),
        ),
        _ev(
          'p2',
          PeerEventType.connect,
          inWindow.add(const Duration(minutes: 20)),
        ),
        _ev('p1', PeerEventType.connect, out24h),
      ];

      final container = ProviderContainer(
        overrides: [
          peerEventsProvider('srv').overrideWith((ref) => events),
        ],
      );
      addTearDown(container.dispose);
      container.listen(serverHistoryProvider('srv'), (_, _) {});

      final history = container.read(serverHistoryProvider('srv'));
      // Out-of-window connect is dropped from the log…
      expect(history.filteredEvents.length, 3);
      expect(history.peers, containsAll(['p1', 'p2']));
      // …but the session that spans the boundary is clipped, not dropped:
      // p1 has the out24h→inWindow session (clipped left) and the
      // inWindow→inWindow+10m session; p2 has its open session.
      expect(history.sessions.length, 3);
      expect(
        history.sessions.any((s) => s.peerPublicKey == 'p2' && s.isOpen),
        isTrue,
      );

      // Filter to p1 only.
      container.read(historyFilterProvider('srv').notifier).setPeer('p1');
      final p1Only = container.read(serverHistoryProvider('srv'));
      expect(
        p1Only.filteredEvents.every((e) => e.peerPublicKey == 'p1'),
        isTrue,
      );
      expect(p1Only.sessions.every((s) => s.peerPublicKey == 'p1'), isTrue);

      // Disable disconnect events.
      container
          .read(historyFilterProvider('srv').notifier)
          .toggleEventType(PeerEventType.disconnect);
      final noDisconnect = container.read(serverHistoryProvider('srv'));
      expect(
        noDisconnect.filteredEvents.every(
          (e) => e.type == PeerEventType.connect,
        ),
        isTrue,
      );
    });

    test('orders filteredEvents newest first', () {
      final now = DateTime.now().toUtc();
      final events = [
        _ev(
          'p1',
          PeerEventType.connect,
          now.subtract(const Duration(hours: 2)),
        ),
        _ev(
          'p1',
          PeerEventType.connect,
          now.subtract(const Duration(hours: 1)),
        ),
      ];
      final container = ProviderContainer(
        overrides: [
          peerEventsProvider('srv').overrideWith((ref) => events),
        ],
      );
      addTearDown(container.dispose);
      container.listen(serverHistoryProvider('srv'), (_, _) {});
      final history = container.read(serverHistoryProvider('srv'));
      expect(
        history.filteredEvents.first.serverTimestamp.isAfter(
          history.filteredEvents.last.serverTimestamp,
        ),
        isTrue,
      );
    });
  });
}
