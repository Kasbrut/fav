import 'package:fav/features/help/presentation/help_hub_screen.dart';
import 'package:fav/features/help/presentation/widgets/help_category_tile.dart';
import 'package:fav/features/help/presentation/widgets/help_coffee_card.dart';
import 'package:fav/features/help/presentation/widgets/help_featured_card.dart';
import 'package:fav/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

Widget _wrap(Widget child) {
  return MaterialApp.router(
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
        GoRoute(path: '/', builder: (_, _) => child),
        GoRoute(
          path: '/help/getting-started',
          builder: (_, _) => const Scaffold(),
        ),
        GoRoute(path: '/help/glossary', builder: (_, _) => const Scaffold()),
        GoRoute(path: '/help/errors', builder: (_, _) => const Scaffold()),
        GoRoute(path: '/help/firewall', builder: (_, _) => const Scaffold()),
        GoRoute(path: '/help/faq', builder: (_, _) => const Scaffold()),
        GoRoute(path: '/help/resources', builder: (_, _) => const Scaffold()),
        GoRoute(
          path: '/help/report-issue',
          builder: (_, _) => const Scaffold(),
        ),
        GoRoute(path: '/help/donate', builder: (_, _) => const Scaffold()),
      ],
    ),
  );
}

void main() {
  testWidgets('shows featured, category and coffee cards', (tester) async {
    // Use a tall viewport so all list items are rendered without scrolling.
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_wrap(const HelpHubScreen()));
    await tester.pumpAndSettle();
    expect(find.byType(HelpFeaturedCard), findsOneWidget);
    expect(find.byType(HelpCategoryTile), findsNWidgets(6));
    expect(find.byType(HelpCoffeeCard), findsOneWidget);
  });
}
