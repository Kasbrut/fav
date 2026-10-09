import 'dart:async';

import 'package:fav/core/router/app_router.dart';
import 'package:fav/core/theme/app_theme.dart';
import 'package:fav/features/settings/application/app_reset_service.dart';
import 'package:fav/features/settings/presentation/post_wipe_screen.dart';
import 'package:fav/features/settings/presentation/widgets/danger_zone_section.dart';
import 'package:fav/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// [AppResetService] fake whose `wipe()` calls each stay pending until
/// their per-call completer is resolved, so tests can observe the app state
/// *while* a wipe runs — and drive a failed attempt followed by a retry.
class _GatedResetService extends AppResetService {
  _GatedResetService() : super(deleteAllSecureEntries: _noop);
  final List<Completer<void>> gates = [];
  bool get started => gates.isNotEmpty;
  Completer<void> get gate => gates.first;
  @override
  Future<void> wipe() {
    final gate = Completer<void>();
    gates.add(gate);
    return gate.future;
  }
}

Future<void> _noop() async {}

void main() {
  Future<AppLocalizations> loadEn() =>
      AppLocalizations.delegate.load(const Locale('en'));

  Future<void> pumpAndConfirmWipe(
    WidgetTester tester,
    AppLocalizations l10n,
    _GatedResetService service,
  ) async {
    final router = GoRouter(
      initialLocation: '/here',
      routes: [
        GoRoute(
          path: '/here',
          builder: (_, _) => const Scaffold(
            body: SingleChildScrollView(child: DangerZoneSection()),
          ),
        ),
        GoRoute(
          path: postWipeRoute,
          // Mirror the production guard (audit H1): the navigation must
          // carry the confirmation token or the wipe screen is unreachable.
          redirect: (context, state) => state.extra == true ? null : '/here',
          builder: (_, _) => const PostWipeScreen(),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appResetServiceProvider.overrideWithValue(service)],
        child: MaterialApp.router(
          routerConfig: router,
          // The failure view's CodeBlock resolves the app's semantic-colors
          // theme extension; the bare Material theme lacks it.
          theme: lightTheme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Open the wipe flow.
    await tester.tap(
      find.widgetWithText(FilledButton, l10n.settingsWipeButton),
    );
    await tester.pumpAndSettle();
    // Dialog 1: continue.
    await tester.tap(
      find.widgetWithText(FilledButton, l10n.settingsWipeDialog1Continue),
    );
    await tester.pumpAndSettle();
    // Dialog 2: type the confirm word, then confirm.
    await tester.enterText(
      find.byType(TextField),
      l10n.settingsWipeConfirmWord,
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(FilledButton, l10n.settingsWipeDialog2Action),
    );
    // Dialog dismissal + navigation + route transition. No pumpAndSettle —
    // the post-wipe screen shows an animating spinner while wipe() is
    // pending; the fixed pump runs the ~300 ms page transition to its end.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
  }

  testWidgets(
    'wipe confirmation navigates to the post-wipe screen, then wipes (M11)',
    (tester) async {
      final l10n = await loadEn();
      final service = _GatedResetService();
      await pumpAndConfirmWipe(tester, l10n, service);

      // The stack is replaced BEFORE the boxes close: no screen watching a
      // box-backed provider stays mounted while the wipe runs (audit M11).
      expect(find.byType(PostWipeScreen), findsOneWidget);
      expect(find.byType(DangerZoneSection), findsNothing);
      expect(service.started, isTrue);
      // Still in progress: the success title is not up yet.
      expect(find.text(l10n.settingsPostWipeTitle), findsNothing);

      service.gate.complete();
      await tester.pumpAndSettle();

      expect(find.text(l10n.settingsPostWipeTitle), findsOneWidget);
      expect(find.text(l10n.settingsPostWipeBody), findsOneWidget);
      // The success block must sit in the middle of the screen: the column
      // used to shrink-wrap its widest child and anchor left (device test
      // 2026-08-19). Default test surface is 800 logical px wide.
      expect(
        tester.getCenter(find.text(l10n.settingsPostWipeTitle)).dx,
        closeTo(400, 1),
      );
    },
  );

  testWidgets(
    'a failed wipe still lands on the post-wipe screen with the error (M11)',
    (tester) async {
      final l10n = await loadEn();
      final service = _GatedResetService();
      await pumpAndConfirmWipe(tester, l10n, service);

      service.gate.completeError(StateError('boxes still locked'));
      await tester.pumpAndSettle();

      // A mid-wipe failure leaves the local data half-deleted: the app must
      // not keep running on closed boxes — the terminal screen stays, says
      // honestly that the erase failed (not the success body), and shows
      // the technical reason.
      expect(find.byType(PostWipeScreen), findsOneWidget);
      expect(find.text(l10n.settingsWipeFailedTitle), findsOneWidget);
      expect(find.text(l10n.settingsWipeFailedBody), findsOneWidget);
      expect(find.textContaining('boxes still locked'), findsOneWidget);
      expect(find.text(l10n.settingsPostWipeTitle), findsNothing);
    },
  );

  testWidgets(
    'the failure view offers a retry that re-runs the wipe (H3)',
    (tester) async {
      final l10n = await loadEn();
      final service = _GatedResetService();
      await pumpAndConfirmWipe(tester, l10n, service);

      service.gates.single.completeError(StateError('locked'));
      await tester.pumpAndSettle();
      expect(find.text(l10n.settingsWipeFailedTitle), findsOneWidget);

      await tester.tap(find.text(l10n.actionRetry));
      await tester.pump();
      expect(service.gates, hasLength(2));

      service.gates[1].complete();
      await tester.pumpAndSettle();
      expect(find.text(l10n.settingsPostWipeTitle), findsOneWidget);
    },
  );
}
