import 'package:fav/core/theme/app_theme.dart';
import 'package:fav/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pumps [child] inside a themed, localised [MaterialApp] for widget tests.
///
/// The child is given a fixed 360 px width so layout widgets resolve their
/// constraints. Use [brightness] to render either the light or dark theme.
/// Set [settle] to false for children that hold a perpetual animation (e.g.
/// an indeterminate progress indicator), which would never let
/// `pumpAndSettle` complete.
Future<void> pumpThemed(
  WidgetTester tester,
  Widget child, {
  Brightness brightness = Brightness.light,
  bool settle = true,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: brightness == Brightness.light ? lightTheme : darkTheme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Center(
          child: SizedBox(width: 360, child: child),
        ),
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump();
  }
}
