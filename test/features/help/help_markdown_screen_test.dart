import 'package:fav/features/help/presentation/widgets/help_markdown_screen.dart';
import 'package:fav/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget app(Widget home, {Locale? locale}) {
    return MaterialApp(
      locale: locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: home,
    );
  }

  testWidgets('loads the asset once and keeps it across rebuilds', (
    tester,
  ) async {
    var calls = 0;
    Future<String> loader(String path) async {
      calls++;
      return '# Hello help';
    }

    Widget build() => app(
      HelpMarkdownScreen(title: 'T', assetStem: 'faq/faq', loadAsset: loader),
    );
    await tester.pumpWidget(build());
    await tester.pumpAndSettle();
    expect(find.text('Hello help'), findsOneWidget);
    expect(calls, 1);

    // A rebuild of the same screen must not reload the asset.
    await tester.pumpWidget(build());
    await tester.pumpAndSettle();
    expect(calls, 1);
  });

  testWidgets('shows an error view whose retry reloads', (tester) async {
    var fail = true;
    var calls = 0;
    Future<String> loader(String path) async {
      calls++;
      if (fail) throw StateError('asset missing');
      return '# Recovered body';
    }

    await tester.pumpWidget(
      app(
        HelpMarkdownScreen(
          title: 'T',
          assetStem: 'faq/faq',
          loadAsset: loader,
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Both the locale and the EN fallback failed → error view, not an
    // endless spinner.
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('This page could not be loaded.'), findsOneWidget);
    expect(calls, 2);

    fail = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Recovered body'), findsOneWidget);
  });

  testWidgets('falls back to the English asset for a missing locale', (
    tester,
  ) async {
    final requested = <String>[];
    Future<String> loader(String path) async {
      requested.add(path);
      if (!path.endsWith('.en.md')) throw StateError('missing');
      return '# English fallback';
    }

    await tester.pumpWidget(
      app(
        HelpMarkdownScreen(
          title: 'T',
          assetStem: 'faq/faq',
          loadAsset: loader,
        ),
        locale: const Locale('it'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('English fallback'), findsOneWidget);
    expect(requested, [
      'lib/assets/help/faq/faq.it.md',
      'lib/assets/help/faq/faq.en.md',
    ]);
  });
}
