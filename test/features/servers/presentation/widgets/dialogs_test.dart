import 'package:fav/features/servers/domain/host_key_fingerprint.dart';
import 'package:fav/features/servers/presentation/widgets/host_key_dialog.dart';
import 'package:fav/features/servers/presentation/widgets/password_prompt_dialog.dart';
import 'package:fav/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tests for the host key and password prompt dialogs.
void main() {
  HostKeyFingerprint fingerprint() => HostKeyFingerprint(
    host: '203.0.113.5',
    port: 22,
    keyType: 'ssh-ed25519',
    hashAlgorithm: 'md5',
    fingerprint: 'aa:bb:cc',
    pinnedAt: DateTime(2026, 5, 18),
  );

  Future<void> pumpHost(
    WidgetTester tester,
    Future<void> Function(BuildContext context) onPressed,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => onPressed(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('host key dialog returns true when the user connects', (
    tester,
  ) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    bool? result;
    await pumpHost(tester, (context) async {
      result = await showHostKeyDialog(context, fingerprint());
    });

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.actionConnect));
    await tester.pumpAndSettle();

    expect(result, isTrue);
  });

  testWidgets(
    'host key dialog shows the algorithm-labelled fingerprint inline',
    (
      tester,
    ) async {
      await pumpHost(tester, (context) async {
        await showHostKeyDialog(context, fingerprint());
      });

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // The fingerprint is shown inline (spec §10) and labelled with its hash
      // algorithm so it can be compared against `ssh-keygen … -E md5`.
      expect(find.text('MD5:aa:bb:cc'), findsOneWidget);
    },
  );

  testWidgets('host key dialog returns false when cancelled', (tester) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    bool? result;
    await pumpHost(tester, (context) async {
      result = await showHostKeyDialog(context, fingerprint());
    });

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.actionCancel));
    await tester.pumpAndSettle();

    expect(result, isFalse);
  });

  testWidgets('password prompt returns the entered password', (tester) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    String? result;
    await pumpHost(tester, (context) async {
      result = await showPasswordPrompt(context, 'root@203.0.113.5');
    });

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'super-secret');
    await tester.tap(find.text(l10n.actionConfirm));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpAndSettle();

    expect(result, 'super-secret');
  });

  testWidgets('password prompt returns null when cancelled', (tester) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    String? result = 'unset';
    await pumpHost(tester, (context) async {
      result = await showPasswordPrompt(context, 'root@203.0.113.5');
    });

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.actionCancel));
    await tester.pumpAndSettle();

    expect(result, isNull);
  });
}
