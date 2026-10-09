import 'package:fav/features/monitoring/application/history_provider.dart';
import 'package:fav/features/monitoring/presentation/history/history_filter_bar.dart';
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

void main() {
  testWidgets('dropdown items show labels for known peers', (tester) async {
    final repo = StaticPeerRepository([_peer('Phone', 'KEY_PHONE_LONG')]);
    await pumpThemed(
      tester,
      ProviderScope(
        overrides: [peerRepositoryProvider.overrideWithValue(repo)],
        child: const HistoryPeerFilter(
          serverId: 'srv',
          availablePeers: ['KEY_PHONE_LONG', 'KEY_UNKNOWN_LONG'],
        ),
      ),
    );

    await tester.tap(find.byType(DropdownButtonFormField<String?>));
    await tester.pumpAndSettle();

    expect(find.text('Phone').last, findsOneWidget);
    expect(find.text('KEY_UNKN…').last, findsOneWidget);
  });

  testWidgets('selecting a labelled item still sets the raw pubkey filter', (
    tester,
  ) async {
    final repo = StaticPeerRepository([_peer('Phone', 'KEY_PHONE_LONG')]);
    late ProviderContainer container;
    await pumpThemed(
      tester,
      ProviderScope(
        overrides: [peerRepositoryProvider.overrideWithValue(repo)],
        child: Builder(
          builder: (context) {
            container = ProviderScope.containerOf(context);
            return const HistoryPeerFilter(
              serverId: 'srv',
              availablePeers: ['KEY_PHONE_LONG', 'KEY_UNKNOWN_LONG'],
            );
          },
        ),
      ),
    );

    await tester.tap(find.byType(DropdownButtonFormField<String?>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Phone').last);
    await tester.pumpAndSettle();

    expect(
      container.read(historyFilterProvider('srv')).peerPublicKey,
      'KEY_PHONE_LONG',
    );
  });
}
