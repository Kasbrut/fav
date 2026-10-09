import 'package:fav/core/theme/app_text_theme.dart';
import 'package:fav/core/theme/app_theme.dart';
import 'package:fav/features/monitoring/domain/connection_session.dart';
import 'package:fav/features/monitoring/presentation/history/connection_timeline_chart.dart';
import 'package:fav/features/peers/application/peers_controller.dart';
import 'package:fav/features/peers/data/hive_peer_repository.dart';
import 'package:fav/features/peers/domain/peer.dart';
import 'package:fav/features/peers/domain/peer_repository.dart';
import 'package:fav/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../support/static_peer_repository.dart';
import '../../../../support/widget_harness.dart';

/// A mutable in-memory [PeerRepository] that allows replacing the peer list
/// mid-test, enabling provider invalidation to drive live-rename scenarios.
class _MutablePeerRepository implements PeerRepository {
  _MutablePeerRepository(List<Peer> initial)
    : _peers = List<Peer>.from(initial);
  List<Peer> _peers;

  void setPeers(List<Peer> next) {
    _peers = List<Peer>.from(next);
  }

  @override
  Future<List<Peer>> getAll() async => _peers;

  @override
  Future<Peer?> getById(String id) async {
    final m = _peers.where((p) => p.id == id);
    return m.isEmpty ? null : m.first;
  }

  @override
  Future<List<Peer>> getByServerId(String serverId) async =>
      _peers.where((p) => p.serverId == serverId).toList();

  @override
  Future<void> save(Peer peer) async {}

  @override
  Future<void> delete(String id) async {}
}

Peer _peer({
  required String id,
  required String label,
  required String publicKey,
}) => Peer(
  id: id,
  serverId: 'srv',
  label: label,
  address: '10.13.13.2/32',
  publicKey: publicKey,
  createdAt: DateTime.utc(2026),
);

ConnectionSession _session(String pk, DateTime start, {DateTime? end}) =>
    ConnectionSession(peerPublicKey: pk, start: start, end: end);

void main() {
  final windowEnd = DateTime.utc(2026, 5, 27, 12);
  final windowStart = windowEnd.subtract(const Duration(hours: 1));

  testWidgets('renders labels for known peers, short pubkey for unknown', (
    tester,
  ) async {
    final repo = StaticPeerRepository([
      _peer(id: 'p1', label: 'Phone', publicKey: 'KEY_PHONE_LONG_ENOUGH'),
    ]);
    await pumpThemed(
      tester,
      ProviderScope(
        overrides: [peerRepositoryProvider.overrideWithValue(repo)],
        child: ConnectionTimelineChart(
          serverId: 'srv',
          sessions: [
            _session(
              'KEY_PHONE_LONG_ENOUGH',
              windowStart.add(const Duration(minutes: 10)),
              end: windowStart.add(const Duration(minutes: 30)),
            ),
            _session(
              'KEY_UNKNOWN_PEER_XYZ',
              windowStart.add(const Duration(minutes: 5)),
              end: windowStart.add(const Duration(minutes: 8)),
            ),
          ],
          windowStart: windowStart,
          windowEnd: windowEnd,
        ),
      ),
    );

    expect(find.text('Phone'), findsOneWidget);
    expect(find.text('KEY_UNKN…'), findsOneWidget);
  });

  testWidgets('orders rows: labelled peers (alphabetical) before unlabelled', (
    tester,
  ) async {
    final repo = StaticPeerRepository([
      _peer(id: 'p1', label: 'Zeta', publicKey: 'KEY_Z'),
      _peer(id: 'p2', label: 'alpha', publicKey: 'KEY_A'),
    ]);
    await pumpThemed(
      tester,
      ProviderScope(
        overrides: [peerRepositoryProvider.overrideWithValue(repo)],
        child: ConnectionTimelineChart(
          serverId: 'srv',
          sessions: [
            _session('KEY_Z', windowStart.add(const Duration(minutes: 10))),
            _session('KEY_A', windowStart.add(const Duration(minutes: 20))),
            _session(
              'KEY_UNKNOWN_LONG_ENOUGH',
              windowStart.add(const Duration(minutes: 30)),
            ),
          ],
          windowStart: windowStart,
          windowEnd: windowEnd,
        ),
      ),
    );

    final alphaY = tester.getCenter(find.text('alpha')).dy;
    final zetaY = tester.getCenter(find.text('Zeta')).dy;
    final unknownY = tester.getCenter(find.text('KEY_UNKN…')).dy;
    expect(alphaY, lessThan(zetaY));
    expect(zetaY, lessThan(unknownY));
  });

  testWidgets('label uses monospace only for pubkey fallback rows', (
    tester,
  ) async {
    final repo = StaticPeerRepository([
      _peer(id: 'p1', label: 'Phone', publicKey: 'KEY_PHONE_LONG'),
    ]);
    await pumpThemed(
      tester,
      ProviderScope(
        overrides: [peerRepositoryProvider.overrideWithValue(repo)],
        child: ConnectionTimelineChart(
          serverId: 'srv',
          sessions: [
            _session(
              'KEY_PHONE_LONG',
              windowStart.add(const Duration(minutes: 5)),
            ),
            _session(
              'KEY_UNKNOWN_LONG',
              windowStart.add(const Duration(minutes: 15)),
            ),
          ],
          windowStart: windowStart,
          windowEnd: windowEnd,
        ),
      ),
    );

    final phoneText = tester.widget<Text>(find.text('Phone'));
    final unknownText = tester.widget<Text>(find.text('KEY_UNKN…'));
    expect(phoneText.style?.fontFamily, isNot(kMonospacePrimaryFont));
    expect(unknownText.style?.fontFamily, kMonospacePrimaryFont);
  });

  testWidgets(
    'bottom-sheet title shows the label and updates on live rename',
    (tester) async {
      final repo = _MutablePeerRepository([
        _peer(id: 'p1', label: 'Phone', publicKey: 'KEY_PHONE_LONG'),
      ]);

      // ProviderScope must be the outermost widget so that the Consumer
      // inside the bottom-sheet modal route can find it. pumpThemed puts
      // MaterialApp on the outside which would make the modal route's context
      // sit outside the ProviderScope.
      late ProviderContainer container;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [peerRepositoryProvider.overrideWithValue(repo)],
          child: Builder(
            builder: (outerContext) {
              container = ProviderScope.containerOf(outerContext);
              return MaterialApp(
                theme: lightTheme,
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: Scaffold(
                  body: Center(
                    child: SizedBox(
                      width: 360,
                      child: ConnectionTimelineChart(
                        serverId: 'srv',
                        sessions: [
                          _session(
                            'KEY_PHONE_LONG',
                            windowStart.add(const Duration(minutes: 10)),
                            end: windowStart.add(const Duration(minutes: 30)),
                          ),
                        ],
                        windowStart: windowStart,
                        windowEnd: windowEnd,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open the session sheet by tapping the session bar (GestureDetector
      // inside the chart's Stack).
      await tester.tap(
        find
            .descendant(
              of: find.byType(ConnectionTimelineChart),
              matching: find.byType(GestureDetector),
            )
            .first,
      );
      await tester.pumpAndSettle();

      // Initial title is the label. The sheet and the chart row behind it
      // both show "Phone", so there may be two matches.
      expect(find.text('Phone'), findsAtLeastNWidgets(1));

      // Mutate the repo and invalidate so the Consumer inside the sheet
      // rebuilds.
      repo.setPeers([
        Peer(
          id: 'p1',
          serverId: 'srv',
          label: 'Mobile',
          address: '10.13.13.2/32',
          publicKey: 'KEY_PHONE_LONG',
          createdAt: DateTime.utc(2026),
        ),
      ]);
      container.invalidate(peersControllerProvider('srv'));
      await tester.pumpAndSettle();

      // The sheet title (and the chart row behind it) now reflect the new
      // label. Both the sheet title and the chart row label update, so there
      // may be two matches for "Mobile". "Phone" must be gone entirely.
      expect(find.text('Mobile'), findsAtLeastNWidgets(1));
      expect(find.text('Phone'), findsNothing);
    },
  );
}
