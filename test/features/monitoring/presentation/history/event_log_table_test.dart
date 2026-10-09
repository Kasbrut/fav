import 'package:fav/core/theme/app_text_theme.dart';
import 'package:fav/features/monitoring/domain/peer_event.dart';
import 'package:fav/features/monitoring/presentation/history/event_log_table.dart';
import 'package:fav/features/peers/data/hive_peer_repository.dart';
import 'package:fav/features/peers/domain/peer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../support/static_peer_repository.dart';
import '../../../../support/widget_harness.dart';

Peer _peer(String label, String pk) => Peer(
  id: pk,
  serverId: 'srv',
  label: label,
  address: '10.13.13.2/32',
  publicKey: pk,
  createdAt: DateTime.utc(2026),
);

PeerEvent _ev(String pk, PeerEventType type) => PeerEvent(
  serverId: 'srv',
  peerPublicKey: pk,
  type: type,
  serverTimestamp: DateTime.utc(2026, 5, 27, 12),
  rx: 0,
  tx: 0,
  latestHandshake: 0,
);

void main() {
  testWidgets('subtitle shows label for known peer (proportional font)', (
    tester,
  ) async {
    final repo = StaticPeerRepository([_peer('Phone', 'KEY_PHONE_LONG')]);
    await pumpThemed(
      tester,
      ProviderScope(
        overrides: [peerRepositoryProvider.overrideWithValue(repo)],
        child: EventLogTable(
          serverId: 'srv',
          events: [_ev('KEY_PHONE_LONG', PeerEventType.connect)],
        ),
      ),
    );

    final subtitleFinder = find.textContaining('Phone');
    expect(subtitleFinder, findsOneWidget);
    final subtitle = tester.widget<Text>(subtitleFinder);
    expect(subtitle.style?.fontFamily, isNot(kMonospacePrimaryFont));
  });

  testWidgets('caps the log and reveals older events on demand', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 8000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repo = StaticPeerRepository([_peer('Phone', 'KEY_PHONE_LONG')]);
    final events = List.generate(
      101,
      (_) => _ev('KEY_PHONE_LONG', PeerEventType.connect),
    );
    await pumpThemed(
      tester,
      ProviderScope(
        overrides: [peerRepositoryProvider.overrideWithValue(repo)],
        child: EventLogTable(serverId: 'srv', events: events),
      ),
    );

    // 101 events, cap 100 → one hidden, behind a labelled button.
    expect(find.text('Show 1 older event'), findsOneWidget);
    await tester.tap(find.text('Show 1 older event'));
    await tester.pumpAndSettle();
    expect(find.text('Show 1 older event'), findsNothing);
  });

  testWidgets('tapping a log row opens the event detail sheet', (tester) async {
    final repo = StaticPeerRepository([_peer('Phone', 'KEY_PHONE_LONG')]);
    await pumpThemed(
      tester,
      ProviderScope(
        overrides: [peerRepositoryProvider.overrideWithValue(repo)],
        child: EventLogTable(
          serverId: 'srv',
          events: [_ev('KEY_PHONE_LONG', PeerEventType.connect)],
        ),
      ),
    );

    await tester.tap(find.byType(InkWell).first);
    await tester.pumpAndSettle();

    // "Time" only appears in the detail sheet, not in the row.
    expect(find.text('Time'), findsOneWidget);
  });

  testWidgets(
    'subtitle falls back to short pubkey in monospace for unknown peer',
    (tester) async {
      final repo = StaticPeerRepository(const []);
      await pumpThemed(
        tester,
        ProviderScope(
          overrides: [peerRepositoryProvider.overrideWithValue(repo)],
          child: EventLogTable(
            serverId: 'srv',
            events: [_ev('KEY_UNKNOWN_LONG', PeerEventType.connect)],
          ),
        ),
      );

      final subtitleFinder = find.textContaining('KEY_UNKN…');
      expect(subtitleFinder, findsOneWidget);
      final subtitle = tester.widget<Text>(subtitleFinder);
      expect(subtitle.style?.fontFamily, kMonospacePrimaryFont);
    },
  );
}
