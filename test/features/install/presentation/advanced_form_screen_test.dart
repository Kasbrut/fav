import 'package:fav/core/theme/app_theme.dart';
import 'package:fav/features/install/presentation/advanced_form_screen.dart';
import 'package:fav/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pumpScreen(WidgetTester tester) async {
  // Tall viewport so the whole form (including the bottom action buttons)
  // is laid out, not virtualized out of the ListView.
  tester.view.physicalSize = const Size(1200, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: lightTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const AdvancedFormScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Taps the toggle in the first switch row (SSH hardening).
Future<void> _toggleHardening(WidgetTester tester) async {
  await tester.tap(find.byType(Switch).first);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('VPN subnet editor keeps the fixed /24 outside the input', (
    tester,
  ) async {
    await _pumpScreen(tester);

    await tester.tap(find.text('VPN subnet'));
    await tester.pumpAndSettle();

    final field = tester.widget<TextFormField>(find.byType(TextFormField));
    expect(field.controller!.text, '10.13.13.0');
    expect(find.text('/24'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField), '10.44.0.0');
    await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
    await tester.pumpAndSettle();

    expect(find.text('10.44.0.0/24'), findsOneWidget);
  });

  testWidgets('switch rows carry plain-language descriptions', (tester) async {
    await _pumpScreen(tester);

    expect(
      find.text(
        'Locks down the whole server: turns off password and root SSH '
        'sign-in (key login only) and adds brute-force protection, after '
        'checking your login still works.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Tracks peer connection status so you can see who is '
        'connected.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('enabling SSH hardening reveals the lockout-protection notice', (
    tester,
  ) async {
    await _pumpScreen(tester);

    // Hidden until the risky option is actually turned on.
    expect(find.text('Protected against lockout'), findsNothing);

    await _toggleHardening(tester);

    expect(find.text('Protected against lockout'), findsOneWidget);
    expect(find.text('What is SSH hardening?'), findsOneWidget);
  });

  testWidgets('Restore defaults confirms, then resets and confirms', (
    tester,
  ) async {
    await _pumpScreen(tester);
    await _toggleHardening(tester);
    expect(find.text('Protected against lockout'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Restore defaults'));
    await tester.pumpAndSettle();

    // A confirmation is required before the reset happens.
    expect(find.text('Restore default options?'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Restore defaults'));
    await tester.pumpAndSettle();

    // Hardening is back to its (off) default, so the notice is gone, and the
    // reset is acknowledged.
    expect(find.text('Protected against lockout'), findsNothing);
    expect(find.text('Default options restored.'), findsOneWidget);
  });

  testWidgets('Restore defaults can be cancelled', (tester) async {
    await _pumpScreen(tester);
    await _toggleHardening(tester);

    await tester.tap(find.widgetWithText(TextButton, 'Restore defaults'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    // Nothing was reset: the hardening notice is still showing.
    expect(find.text('Protected against lockout'), findsOneWidget);
  });
}
