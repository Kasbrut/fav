// The SSH key fixture is a single unsplittable base64 token.
// ignore_for_file: lines_longer_than_80_chars

import 'package:fav/features/servers/data/ssh_key_file_importer.dart';
import 'package:fav/features/servers/presentation/widgets/ssh_key_editor.dart';
import 'package:fav/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _ed25519 =
    'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILumuaB4RSmE61UE6zVVVutcGA5HoayYq1PhFhdkFg9e user@laptop';
const _ed25519Fingerprint =
    'SHA256:60LKL82Fi5QVhVaE7DYVwGLRjiwHzCvi8RupJ+rqD3I';

Future<void> _pumpDialogHost(
  WidgetTester tester, {
  SshKeyFileImporter? importer,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        if (importer != null)
          sshKeyFileImporterProvider.overrideWithValue(importer),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                final result = await showAddSshKeyDialog(context);
                // Stash the result on the button label for assertion.
                _lastResult = result;
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
}

String? _lastResult;

void main() {
  setUp(() => _lastResult = null);

  group('SshKeyListCard', () {
    testWidgets('shows the empty state and an add button', (tester) async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SshKeyListCard(
              keys: const [],
              onAdd: () {},
              onRemove: (_) {},
            ),
          ),
        ),
      );
      expect(find.text(l10n.sshKeysEmpty), findsOneWidget);
      expect(find.text(l10n.actionAddSshKey), findsOneWidget);
    });

    testWidgets('renders a key with its fingerprint and removes it', (
      tester,
    ) async {
      String? removed;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SshKeyListCard(
              keys: const [_ed25519],
              onAdd: () {},
              onRemove: (k) => removed = k,
            ),
          ),
        ),
      );
      expect(find.text('user@laptop'), findsOneWidget);
      expect(find.text(_ed25519Fingerprint), findsOneWidget);

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pump();
      expect(removed, _ed25519);
    });

    testWidgets('disables actions when busy', (tester) async {
      var added = false;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SshKeyListCard(
              keys: const [_ed25519],
              busy: true,
              onAdd: () => added = true,
              onRemove: (_) {},
            ),
          ),
        ),
      );
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      await tester.tap(find.text(l10n.actionAddSshKey));
      await tester.pump();
      expect(added, isFalse);
    });
  });

  group('showAddSshKeyDialog', () {
    testWidgets('returns the normalized line for a valid pasted key', (
      tester,
    ) async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      await _pumpDialogHost(tester);
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField), '  $_ed25519  ');
      await tester.tap(find.text(l10n.actionAdd));
      await tester.pumpAndSettle();

      expect(_lastResult, _ed25519);
    });

    testWidgets('shows a validation error and does not pop for junk', (
      tester,
    ) async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      await _pumpDialogHost(tester);
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField), 'not a key');
      await tester.tap(find.text(l10n.actionAdd));
      await tester.pumpAndSettle();

      expect(find.text(l10n.validationSshPublicKey), findsOneWidget);
      // Dialog still open.
      expect(find.text(l10n.sshKeyAddTitle), findsOneWidget);
    });

    testWidgets('imports a key from a file into the field', (tester) async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      await _pumpDialogHost(tester, importer: () async => '$_ed25519\n');
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text(l10n.actionImportFromFile));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.actionAdd));
      await tester.pumpAndSettle();

      expect(_lastResult, _ed25519);
    });
  });
}
