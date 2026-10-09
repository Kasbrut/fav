import 'dart:ui' show Tristate;

import 'package:fav/features/shell/presentation/shell_extra_keys_bar.dart';
import 'package:fav/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

void main() {
  late List<TerminalKey> keys;
  late List<String> chars;
  late int ctrlToggles;
  late int altToggles;
  late int copies;
  late int pastes;

  setUp(() {
    keys = [];
    chars = [];
    ctrlToggles = 0;
    altToggles = 0;
    copies = 0;
    pastes = 0;
  });

  Future<void> pumpBar(
    WidgetTester tester, {
    bool ctrlActive = false,
    bool altActive = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ShellExtraKeysBar(
            ctrlActive: ctrlActive,
            altActive: altActive,
            onKey: keys.add,
            onChar: chars.add,
            onToggleCtrl: () => ctrlToggles++,
            onToggleAlt: () => altToggles++,
            onCopy: () => copies++,
            onPaste: () => pastes++,
          ),
        ),
      ),
    );
  }

  testWidgets('renders every key cap of the two Termux-style rows', (
    tester,
  ) async {
    await pumpBar(tester);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    for (final label in [
      l10n.shellKeyEsc,
      l10n.shellKeyTab,
      l10n.shellKeyCtrl,
      l10n.shellKeyAlt,
      l10n.shellKeyHome,
      l10n.shellKeyEnd,
      l10n.shellKeyPgUp,
      l10n.shellKeyPgDn,
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('/'), findsOneWidget);
    expect(find.text('-'), findsOneWidget);
    for (final icon in [
      Icons.keyboard_arrow_up,
      Icons.keyboard_arrow_down,
      Icons.keyboard_arrow_left,
      Icons.keyboard_arrow_right,
    ]) {
      expect(find.byIcon(icon), findsOneWidget);
    }
  });

  testWidgets('special keys report the matching TerminalKey', (tester) async {
    await pumpBar(tester);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await tester.tap(find.text(l10n.shellKeyEsc));
    await tester.tap(find.text(l10n.shellKeyTab));
    await tester.tap(find.byIcon(Icons.keyboard_arrow_up));
    await tester.tap(find.text(l10n.shellKeyPgDn));
    expect(keys, [
      TerminalKey.escape,
      TerminalKey.tab,
      TerminalKey.arrowUp,
      TerminalKey.pageDown,
    ]);
  });

  testWidgets('character keys report the literal character', (tester) async {
    await pumpBar(tester);
    await tester.tap(find.text('/'));
    await tester.tap(find.text('-'));
    expect(chars, ['/', '-']);
    expect(keys, isEmpty);
  });

  testWidgets('copy and paste keys report their callbacks', (tester) async {
    await pumpBar(tester);
    await tester.tap(find.byIcon(Icons.copy));
    await tester.tap(find.byIcon(Icons.content_paste));
    expect(copies, 1);
    expect(pastes, 1);
    expect(keys, isEmpty);
    expect(chars, isEmpty);
  });

  testWidgets('CTRL and ALT report toggles instead of key events', (
    tester,
  ) async {
    await pumpBar(tester);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await tester.tap(find.text(l10n.shellKeyCtrl));
    await tester.tap(find.text(l10n.shellKeyAlt));
    expect(ctrlToggles, 1);
    expect(altToggles, 1);
    expect(keys, isEmpty);
    expect(chars, isEmpty);
  });

  testWidgets('an armed modifier renders its label in white for contrast', (
    tester,
  ) async {
    await pumpBar(tester, ctrlActive: true);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    Color colorOf(String label) =>
        tester.widget<Text>(find.text(label)).style!.color!;
    // White on the vivid active blue clears WCAG AA (>= 4.5:1); the resting
    // grey would not (3.52:1).
    expect(colorOf(l10n.shellKeyCtrl), Colors.white);
    expect(colorOf(l10n.shellKeyAlt), isNot(Colors.white));
  });

  testWidgets('active modifiers are exposed as selected semantics', (
    tester,
  ) async {
    await pumpBar(tester, ctrlActive: true);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    final ctrl = tester.getSemantics(
      find.bySemanticsLabel(l10n.shellKeyCtrl),
    );
    final alt = tester.getSemantics(find.bySemanticsLabel(l10n.shellKeyAlt));
    expect(ctrl.flagsCollection.isSelected, Tristate.isTrue);
    // ALT is a toggle too: it must expose an explicit "not selected".
    expect(alt.flagsCollection.isSelected, Tristate.isFalse);
    // Plain one-shot keys are not toggles: no selected state at all, or
    // screen readers would announce a spurious "not selected" on every key.
    final esc = tester.getSemantics(find.bySemanticsLabel(l10n.shellKeyEsc));
    expect(esc.flagsCollection.isSelected, Tristate.none);
  });
}
