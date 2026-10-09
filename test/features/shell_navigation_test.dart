import 'package:fav/app.dart';
import 'package:fav/core/router/app_router.dart';
import 'package:fav/core/widgets/responsive_app_bar.dart';
import 'package:fav/features/install/data/ssh/host_key_store.dart';
import 'package:fav/features/servers/data/hive_server_repository.dart';
import 'package:fav/features/settings/application/preferences_controller.dart';
import 'package:fav/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../support/fake_preferences_repository.dart';
import '../support/in_memory_secure_store.dart';
import '../support/server_fakes.dart';

/// Widget tests for the bottom-navigation shell and the stub tab screens.
void main() {
  Future<AppLocalizations> loadEn() {
    return AppLocalizations.delegate.load(const Locale('en'));
  }

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          serverRepositoryProvider.overrideWithValue(FakeServerRepository()),
          hostKeyStoreProvider.overrideWithValue(
            HostKeyStore(InMemorySecureStore()),
          ),
          preferencesRepositoryProvider.overrideWithValue(
            FakePreferencesRepository(),
          ),
        ],
        child: const WireguardProvisionerApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the adaptive navigation switches between the tabs', (
    tester,
  ) async {
    final l10n = await loadEn();
    await pumpApp(tester);

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.text(l10n.serverListTitle), findsOneWidget);

    await tester.tap(find.text(l10n.navSettings));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text(l10n.settingsAboutBody),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text(l10n.settingsAboutBody), findsOneWidget);

    await tester.tap(find.text(l10n.navHelp));
    await tester.pumpAndSettle();
    expect(find.text(l10n.helpHubQuickStartTitle), findsOneWidget);

    await tester.tap(find.text(l10n.navServers));
    await tester.pumpAndSettle();
    expect(find.text(l10n.serverListTitle), findsOneWidget);
  });

  testWidgets('compact layouts use bottom navigation', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpApp(tester);

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
  });

  testWidgets('settings subroutes retain the adaptive shell and header', (
    tester,
  ) async {
    await pumpApp(tester);

    final context = tester.element(find.byType(NavigationRail));
    GoRouter.of(context).go(settingsLanguageRoute);
    await tester.pumpAndSettle();

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(ResponsiveAppBar), findsOneWidget);
  });
}
