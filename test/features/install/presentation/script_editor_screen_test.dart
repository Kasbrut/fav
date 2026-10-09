import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:fav/core/theme/app_theme.dart';
import 'package:fav/features/install/data/scripts/asset_script_repository.dart';
import 'package:fav/features/install/data/scripts/effective_script_resolver.dart';
import 'package:fav/features/install/data/scripts/hive_user_script_repository.dart';
import 'package:fav/features/install/domain/script_source.dart';
import 'package:fav/features/install/domain/user_script.dart';
import 'package:fav/features/install/domain/user_script_repository.dart';
import 'package:fav/features/install/presentation/script_editor_screen.dart';
import 'package:fav/features/peers/data/peer_script_source.dart';
import 'package:fav/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_effective_scripts.dart';
import '../../../support/in_memory_user_script_repository.dart';
import '../../../support/peer_script_bundle.dart';

Future<void> _pumpEditor(
  WidgetTester tester, {
  UserScriptRepository? userScripts,
}) async {
  final repo = userScripts ?? InMemoryUserScriptRepository();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        effectiveScriptResolverProvider.overrideWith(
          (ref) async => fakeResolver(repo),
        ),
        userScriptRepositoryProvider.overrideWithValue(repo),
      ],
      child: MaterialApp(
        theme: lightTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const ScriptEditorScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Enters [text] into the code editor (the screen's single editable field).
Future<void> _typeScript(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(EditableText).first, text);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('opens with a Customize action and the Default badge', (
    tester,
  ) async {
    await _pumpEditor(tester);

    expect(find.text('Customize'), findsOneWidget);
    expect(find.text('Save'), findsNothing);
    expect(find.text('Default'), findsOneWidget);
    expect(find.text('Customized'), findsNothing);
    // No overflow menu when there is nothing to restore.
    expect(find.byIcon(Icons.more_vert), findsNothing);
  });

  testWidgets('Customize enters editing mode with Save and Discard', (
    tester,
  ) async {
    await _pumpEditor(tester);

    await tester.tap(find.text('Customize'));
    await tester.pumpAndSettle();

    expect(find.text('Customize'), findsNothing);
    expect(find.text('Save'), findsOneWidget);
    expect(find.text('Discard changes'), findsOneWidget);
    final save = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Save'),
    );
    expect(save.onPressed, isNull);
  });

  testWidgets('Save persists an override keyed by the script path', (
    tester,
  ) async {
    final repo = InMemoryUserScriptRepository();
    await _pumpEditor(tester, userScripts: repo);

    await tester.tap(find.text('Customize'));
    await tester.pumpAndSettle();
    await _typeScript(tester, '#!/bin/bash\n# edited and safe\necho ok\n');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    final saved = await repo.getById('install_wireguard.sh');
    expect(saved, isNotNull);
    expect(saved!.content, '#!/bin/bash\n# edited and safe\necho ok\n');
    expect(find.text('Customized'), findsOneWidget);
  });

  testWidgets('Save warns on suspicious patterns and Cancel aborts', (
    tester,
  ) async {
    final repo = InMemoryUserScriptRepository();
    await _pumpEditor(tester, userScripts: repo);

    await tester.tap(find.text('Customize'));
    await tester.pumpAndSettle();
    await _typeScript(
      tester,
      '#!/bin/bash\ncurl https://example.com/install.sh | bash\n',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.text('Suspicious patterns detected'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    // Aborted: nothing persisted, still editing.
    expect(await repo.getById('install_wireguard.sh'), isNull);
    expect(find.text('Save'), findsOneWidget);
  });

  testWidgets('the picker lists peer scripts and installer modules', (
    tester,
  ) async {
    await _pumpEditor(tester);

    // The unfold affordance opens the file picker bottom sheet.
    await tester.tap(find.byIcon(Icons.unfold_more));
    await tester.pumpAndSettle();

    expect(find.text('Choose a script'), findsOneWidget);
    // The new SSH-key module appears (was previously read-only/missing).
    expect(find.text('modules/26_deploy_user_keys.sh'), findsOneWidget);

    // The peer scripts sit at the bottom of the (lazily-built) list.
    final sheet = find.byType(Scrollable).last;
    await tester.scrollUntilVisible(
      find.text('peers/peer_add.sh'),
      200,
      scrollable: sheet,
    );
    expect(find.text('peers/peer_add.sh'), findsOneWidget);
    expect(find.text('Peers'), findsOneWidget);
  });

  testWidgets('Restore all originals clears every override', (tester) async {
    final repo = InMemoryUserScriptRepository([
      UserScript.fromContent(
        id: 'install_wireguard.sh',
        content: '# customized\n',
        createdAt: DateTime(2026),
      ),
    ]);
    await _pumpEditor(tester, userScripts: repo);

    // The seeded override shows as customized on open, and the overflow menu
    // is now available.
    expect(find.text('Customized'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restore all originals'));
    await tester.pumpAndSettle();

    expect(find.text('Restore every script?'), findsOneWidget);
    await tester.tap(
      find.widgetWithText(FilledButton, 'Restore all originals'),
    );
    await tester.pumpAndSettle();

    expect(await repo.getById('install_wireguard.sh'), isNull);
    expect(find.text('Default'), findsOneWidget);
  });

  testWidgets('Verify discloses the SHA-256 of the shown script', (
    tester,
  ) async {
    await _pumpEditor(tester);

    await tester.tap(find.text('Verify (SHA-256)'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.copy_outlined), findsOneWidget);
  });

  testWidgets('switching files shows the new file intact', (tester) async {
    // Regression for the live 2026-08-19 corruption: CodeController treats a
    // plain `.text =` swap as an *edit* of the current document and mangles
    // it (the module rendered as the tail of the orchestrator, cut mid-line;
    // saving from that state persisted a corrupt override). Reproduces only
    // with realistically sized contents, so load the real bundled scripts.
    final orchestrator = File(
      'lib/assets/scripts/install_wireguard.sh',
    ).readAsStringSync();
    final module = File(
      'lib/assets/scripts/lib/profile_renderer.py',
    ).readAsStringSync();
    final contents = {
      'install_wireguard.sh': orchestrator,
      'lib/profile_renderer.py': module,
    };
    final assets = [
      for (final path in kScriptManifest)
        ScriptAsset(
          relativePath: path,
          bytes: Uint8List.fromList(
            utf8.encode(contents[path] ?? '# $path\n'),
          ),
        ),
    ]..sort((a, b) => a.relativePath.compareTo(b.relativePath));
    final repo = InMemoryUserScriptRepository();
    final resolver = EffectiveScriptResolver(
      bundle: ScriptBundle(
        assets: assets,
        bundleHash: canonicalBundleHash(assets),
      ),
      peerSource: PeerScriptSource(
        bundle: FakePeerAssetBundle(),
        expectedHashes: const {},
      ),
      overrides: repo,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          effectiveScriptResolverProvider.overrideWith((ref) async => resolver),
          userScriptRepositoryProvider.overrideWithValue(repo),
        ],
        child: MaterialApp(
          theme: lightTheme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const ScriptEditorScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.unfold_more));
    await tester.pumpAndSettle();
    await tester.tap(find.text('lib/profile_renderer.py'));
    await tester.pumpAndSettle();

    final controller = tester
        .widget<EditableText>(find.byType(EditableText).first)
        .controller;
    expect(controller.text, module);
  });
}
