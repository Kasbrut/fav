import 'package:fav/core/errors/app_exception.dart';
import 'package:fav/features/help/presentation/troubleshooting_list_screen.dart';
import 'package:fav/features/help/presentation/widgets/help_category_tile.dart';
import 'package:fav/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  testWidgets('renders one tile per ErrorCode', (tester) async {
    tester.view.physicalSize = const Size(800, 6000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

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
              builder: (ctx, st) => const TroubleshootingListScreen(),
            ),
            GoRoute(
              path: '/help/errors/:code',
              builder: (ctx, st) => const Scaffold(),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byType(HelpCategoryTile),
      findsNWidgets(ErrorCode.values.length),
    );
  });
}
