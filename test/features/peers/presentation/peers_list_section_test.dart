import 'package:fav/core/widgets/app_card.dart';
import 'package:fav/features/monitoring/application/monitor_polling_controller.dart';
import 'package:fav/features/peers/application/peers_controller.dart';
import 'package:fav/features/peers/domain/peer.dart';
import 'package:fav/features/peers/presentation/peers_list_section.dart';
import 'package:fav/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final Peer _peer = Peer(
  id: 'peer-1',
  serverId: 'srv-1',
  label: 'phone-test',
  address: '10.13.13.2/32',
  publicKey: 'pk',
  createdAt: DateTime(2026, 8, 19),
);

/// [PeersController] whose revoke always succeeds, recording the calls.
class _StubPeersController extends PeersController {
  _StubPeersController(this.peers) : super('srv-1');

  final List<Peer> peers;

  int revokeCalls = 0;

  @override
  Future<List<Peer>> build() async => peers;

  @override
  Future<void> revokePeer({
    required Peer peer,
    required String password,
  }) async {
    revokeCalls++;
  }
}

/// Monitor controller that never polls: no snapshot, no timers.
class _StubMonitorController extends MonitorPollingController {
  _StubMonitorController() : super('srv-1');

  @override
  MonitorPollingState build() => const MonitorPollingState();
}

void main() {
  testWidgets('a successful revoke shows a confirmation snackbar', (
    tester,
  ) async {
    final controller = _StubPeersController([_peer]);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          peersControllerProvider('srv-1').overrideWith(() => controller),
          monitorPollingControllerProvider(
            'srv-1',
          ).overrideWith(_StubMonitorController.new),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: PeersListSection(serverId: 'srv-1'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    // Overflow menu → revoke → confirm → password → confirm.
    await tester.tap(find.byTooltip(l10n.actionPeerOptions));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.actionRevokePeer));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.peerRevokeConfirmAction));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'pw');
    await tester.tap(find.text(l10n.actionConfirm));
    await tester.pumpAndSettle();

    expect(controller.revokeCalls, 1);
    expect(find.text(l10n.peerRevokedSnack('phone-test')), findsOneWidget);
  });

  testWidgets('the empty peer card fills the available width', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          peersControllerProvider(
            'srv-1',
          ).overrideWith(() => _StubPeersController(const [])),
          monitorPollingControllerProvider(
            'srv-1',
          ).overrideWith(_StubMonitorController.new),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: PeersListSection(serverId: 'srv-1')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.getSize(find.byType(AppCard)).width,
      tester.getSize(find.byType(PeersListSection)).width,
    );
  });
}
