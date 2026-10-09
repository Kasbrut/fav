import 'dart:async';

import 'package:fav/features/settings/application/preferences_controller.dart';
import 'package:fav/features/settings/domain/app_language.dart';
import 'package:fav/features/settings/domain/locale_choice.dart';
import 'package:fav/features/settings/domain/user_preferences.dart';
import 'package:fav/features/settings/presentation/language_picker_screen.dart';
import 'package:fav/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../support/fake_preferences_repository.dart';

/// Pumps the picker pushed on top of a "home" route so `context.pop()` has a
/// destination, then settles. Returns the router for further navigation.
Future<GoRouter> _pumpPicker(
  WidgetTester tester,
  FakePreferencesRepository repo,
) async {
  // Tall viewport so the lazy ListView builds every language tile.
  tester.view.physicalSize = const Size(800, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const Scaffold(body: Text('home')),
      ),
      GoRoute(
        path: '/language',
        builder: (context, state) => const LanguagePickerScreen(),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        preferencesRepositoryProvider.overrideWithValue(repo),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );
  unawaited(router.push('/language'));
  await tester.pumpAndSettle();
  return router;
}

void main() {
  testWidgets('lists follow-system plus every registered language', (
    tester,
  ) async {
    await _pumpPicker(tester, FakePreferencesRepository());

    expect(find.text('Automatic'), findsOneWidget);
    for (final language in appLanguages) {
      expect(find.text(language.nativeName), findsOneWidget);
    }
  });

  testWidgets('marks the active choice with a check', (tester) async {
    final repo = FakePreferencesRepository(
      UserPreferences.defaults.copyWith(
        localeChoice: LocaleChoice.forCode('de'),
      ),
    );
    await _pumpPicker(tester, repo);

    expect(find.byIcon(Icons.check), findsOneWidget);
    final deTile = find.ancestor(
      of: find.text('Deutsch'),
      matching: find.byType(ListTile),
    );
    expect(
      find.descendant(of: deTile, matching: find.byIcon(Icons.check)),
      findsOneWidget,
    );
  });

  testWidgets('tapping a language persists it and pops', (tester) async {
    final repo = FakePreferencesRepository();
    await _pumpPicker(tester, repo);

    await tester.tap(find.text('Italiano'));
    await tester.pumpAndSettle();

    expect(repo.readSync().localeChoice, LocaleChoice.forCode('it'));
    // Popped back to home.
    expect(find.text('home'), findsOneWidget);
  });
}
