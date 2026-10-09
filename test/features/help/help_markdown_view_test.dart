import 'package:fav/core/theme/app_colors.dart';
import 'package:fav/core/theme/app_theme.dart';
import 'package:fav/features/help/presentation/widgets/help_markdown_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders markdown body text', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: HelpMarkdownView(data: '# Hello\n\nbody text'),
        ),
      ),
    );
    expect(find.text('Hello'), findsOneWidget);
    expect(find.text('body text'), findsOneWidget);
  });

  testWidgets('glossary:// scheme calls the glossary handler', (tester) async {
    String? captured;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HelpMarkdownView(
            data: '[MTU](glossary://mtu)',
            onGlossary: (slug) => captured = slug,
          ),
        ),
      ),
    );
    await tester.tap(find.text('MTU'));
    await tester.pumpAndSettle();
    expect(captured, 'mtu');
  });

  testWidgets('help-error:// scheme calls the error handler', (tester) async {
    String? captured;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HelpMarkdownView(
            data: '[ERR](help-error://ERR-CONN-01)',
            onErrorCode: (code) => captured = code,
          ),
        ),
      ),
    );
    await tester.tap(find.text('ERR'));
    await tester.pumpAndSettle();
    expect(captured, 'ERR-CONN-01');
  });

  testWidgets('http(s) scheme calls the external handler', (tester) async {
    Uri? captured;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HelpMarkdownView(
            data: '[docs](https://example.com)',
            onExternal: (uri) => captured = uri,
          ),
        ),
      ),
    );
    await tester.tap(find.text('docs'));
    await tester.pumpAndSettle();
    expect(captured.toString(), 'https://example.com');
  });

  testWidgets('blockquotes use the theme info surface, not a hardcoded blue', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: darkTheme,
        home: const Scaffold(
          body: HelpMarkdownView(data: '> Heads-up: check the firewall.'),
        ),
      ),
    );

    // The package default paints blockquotes on Colors.blue.shade100, which is
    // unreadable against light text in dark mode (issue #8). Assert the
    // callout instead uses the theme's info surface.
    final decorations = tester
        .widgetList<DecoratedBox>(find.byType(DecoratedBox))
        .map((box) => box.decoration)
        .whereType<BoxDecoration>()
        .map((decoration) => decoration.color)
        .toList();
    expect(decorations, contains(AppColors.darkInfoSurface));
    expect(decorations, isNot(contains(Colors.blue.shade100)));
  });
}
