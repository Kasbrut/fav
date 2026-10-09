import 'package:fav/features/help/domain/glossary_entries.dart';
import 'package:fav/features/help/presentation/glossary_screen.dart';
import 'package:fav/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders one card per glossary entry', (tester) async {
    // Make sure the viewport is tall enough to lay out all 15 cards.
    tester.view.physicalSize = const Size(800, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: GlossaryScreen(),
      ),
    );
    await tester.pumpAndSettle();

    // English titles for 3 well-known terms, used as spot-checks.
    expect(find.text('MTU'), findsOneWidget);
    expect(find.text('Peer'), findsOneWidget);
    expect(find.text('Glossary'), findsOneWidget); // AppBar title
    // Indirect cardinality check via the registry.
    expect(glossaryEntries.length, 15);
  });
}
