import 'package:fav/features/help/presentation/troubleshooting_detail_screen.dart';
import 'package:fav/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders title, cause, fix sections for a known code', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: TroubleshootingDetailScreen(code: 'ERR-CONN-01'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('What happened'), findsOneWidget);
    expect(find.text('Why this happens'), findsOneWidget);
    expect(find.text('How to fix it'), findsOneWidget);
    expect(find.text('ERR-CONN-01'), findsOneWidget); // AppBar title
  });
}
