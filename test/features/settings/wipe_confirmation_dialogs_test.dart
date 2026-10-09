import 'package:fav/features/settings/presentation/widgets/wipe_confirmation_dialogs.dart';
import 'package:fav/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap() {
  return MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: Builder(
        builder: (context) {
          return Center(
            child: ElevatedButton(
              onPressed: () => WipeConfirmationFlow.show(context),
              child: const Text('Trigger'),
            ),
          );
        },
      ),
    ),
  );
}

void main() {
  testWidgets('cancel on the first dialog dismisses', (tester) async {
    await tester.pumpWidget(_wrap());
    await tester.tap(find.text('Trigger'));
    await tester.pumpAndSettle();
    expect(find.text('Erase all local data?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Erase all local data?'), findsNothing);
  });

  testWidgets('Erase button disabled until exact word typed', (tester) async {
    await tester.pumpWidget(_wrap());
    await tester.tap(find.text('Trigger'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    final eraseFinder = find.text('Erase everything');
    expect(eraseFinder, findsOneWidget);

    // Initially disabled.
    var btn = tester.widget<FilledButton>(
      find.ancestor(of: eraseFinder, matching: find.byType(FilledButton)),
    );
    expect(btn.onPressed, isNull);

    // Wrong word.
    await tester.enterText(find.byType(TextField), 'delete');
    await tester.pumpAndSettle();
    btn = tester.widget<FilledButton>(
      find.ancestor(of: eraseFinder, matching: find.byType(FilledButton)),
    );
    expect(btn.onPressed, isNull);

    // Exact word.
    await tester.enterText(find.byType(TextField), 'DELETE');
    await tester.pumpAndSettle();
    btn = tester.widget<FilledButton>(
      find.ancestor(of: eraseFinder, matching: find.byType(FilledButton)),
    );
    expect(btn.onPressed, isNotNull);
  });
}
