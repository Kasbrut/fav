import 'package:fav/features/help/presentation/donate_screen.dart';
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
              builder: (context, state) => const DonateScreen(),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Title appears in the AppBar AND in the markdown H1.
    expect(find.text('Buy me a coffee'), findsAtLeastNWidgets(1));
    // A fragment of the markdown body — confirms rootBundle loaded the asset.
    expect(find.textContaining('99'), findsAtLeastNWidgets(1));
  });
}
