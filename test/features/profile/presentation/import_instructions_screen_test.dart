import 'package:fav/features/profile/presentation/import_instructions_screen.dart';
import 'package:fav/features/profile/presentation/widgets/instruction_store_links.dart';
import 'package:fav/l10n/app_localizations.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

// Asserting on the rendered label text (read from the real localizations, not
// hardcoded) keeps the test independent of which icon each store uses.
Future<AppLocalizations> _pump(
  WidgetTester tester, {
  required TargetPlatform platform,
}) async {
  // The step lists are tall ListViews; grow the surface tall enough that every
  // card in the visible tab is materialized (lazy lists only build what fits in
  // the viewport + cache extent).
  await tester.binding.setSurfaceSize(const Size(800, 4000));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  // The screen reads defaultTargetPlatform once in initState. Override it only
  // across the first build, then clear it (below) so the foundation invariant
  // check at the end of the test body passes — that check runs before any
  // tearDown, so clearing must happen inline. The tearDown is a safety net for
  // the case where pumpAndSettle throws before the inline clear is reached.
  debugDefaultTargetPlatformOverride = platform;
  addTearDown(() => debugDefaultTargetPlatformOverride = null);
  final router = GoRouter(
    initialLocation: '/instructions',
    routes: [
      GoRoute(
        path: '/instructions',
        builder: (_, _) => const ImportInstructionsScreen(serverId: 'srv-1'),
      ),
    ],
  );
  await tester.pumpWidget(
    MaterialApp.router(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
    ),
  );
  await tester.pumpAndSettle();
  debugDefaultTargetPlatformOverride = null;

  return AppLocalizations.delegate.load(const Locale('en'));
}

void main() {
  testWidgets(
    'Android shows the Play Store link and one focused screenshot',
    (tester) async {
      final l10n = await _pump(tester, platform: TargetPlatform.android);

      expect(find.text(l10n.instructionsInstallStorePlayStore), findsOneWidget);
      // App Store only appears on the (offstage) QR tab on Android.
      expect(find.text(l10n.instructionsInstallStoreAppStore), findsNothing);

      expect(
        find.image(
          const AssetImage(
            'lib/assets/help/import/wireguard-android-import.webp',
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.text(l10n.instructionsAndroidProtectionTitle),
        findsOneWidget,
      );
      expect(find.byKey(const Key('client-platform-selector')), findsOneWidget);
    },
  );

  testWidgets('iOS shows the App Store link and one focused screenshot', (
    tester,
  ) async {
    final l10n = await _pump(tester, platform: TargetPlatform.iOS);

    expect(find.text(l10n.instructionsInstallStoreAppStore), findsOneWidget);
    // Play Store only appears on the (offstage) QR tab on iOS.
    expect(find.text(l10n.instructionsInstallStorePlayStore), findsNothing);

    expect(
      find.image(
        const AssetImage(
          'lib/assets/help/import/wireguard-ios-import.webp',
        ),
      ),
      findsOneWidget,
    );
    expect(find.text(l10n.instructionsExternalMeasureTitle), findsOneWidget);
  });

  testWidgets('destination selector offers desktop-specific instructions', (
    tester,
  ) async {
    final l10n = await _pump(tester, platform: TargetPlatform.android);

    await tester.tap(find.byKey(const Key('client-platform-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Windows').last);
    await tester.pumpAndSettle();

    expect(
      find.text(l10n.instructionsDesktopStep1Title('Windows')),
      findsOneWidget,
    );
    expect(find.text(l10n.instructionsExternalMeasureTitle), findsOneWidget);
    expect(find.byType(InstructionStoreLinks), findsNothing);
    expect(find.byKey(const Key('declare-profile-imported')), findsOneWidget);
  });
}
