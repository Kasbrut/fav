import 'package:fav/features/help/presentation/getting_started_screen.dart';
import 'package:fav/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  testWidgets('renders the screen title and the markdown body', (tester) async {
    await tester.pumpWidget(
      MaterialApp.router(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: GoRouter(
          initialLocation: '/',
          routes: [
            GoRoute(
              path: '/',
              builder: (context, state) => const GettingStartedScreen(),
            ),
            GoRoute(
              path: '/help/glossary/:term',
              builder: (context, state) => const Scaffold(),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    // The title appears in the AppBar AND in the markdown H1.
    expect(find.text('Your first server'), findsAtLeastNWidgets(1));
    // Section 1 heading from the markdown content. Confirm rootBundle loaded.
    expect(find.textContaining('virtual machine'), findsAtLeastNWidgets(1));
  });
}
