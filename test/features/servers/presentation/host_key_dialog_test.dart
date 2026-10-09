import 'package:fav/core/theme/app_dimens.dart';
import 'package:fav/core/theme/app_theme.dart';
import 'package:fav/features/servers/domain/host_key_fingerprint.dart';
import 'package:fav/features/servers/presentation/widgets/host_key_dialog.dart';
import 'package:fav/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final fingerprint = HostKeyFingerprint(
    host: '203.0.113.5',
    port: 22,
    keyType: 'ssh-ed25519',
    hashAlgorithm: 'sha256',
    fingerprint: 'AbCdEfGh01234567890123456789012345678901+/x',
    pinnedAt: DateTime(2026, 8, 19),
  );

  Future<AppLocalizations> loadEn() =>
      AppLocalizations.delegate.load(const Locale('en'));

  Future<void> pumpAndOpen(
    WidgetTester tester, {
    required bool previouslyTrusted,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: lightTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showHostKeyDialog(
              context,
              fingerprint,
              previouslyTrusted: previouslyTrusted,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('a first connection uses the TOFU copy', (tester) async {
    final l10n = await loadEn();
    await pumpAndOpen(tester, previouslyTrusted: false);
    expect(find.text(l10n.hostKeyBody('203.0.113.5')), findsOneWidget);
  });

  testWidgets('the dialog stays compact on a wide display', (tester) async {
    tester.view.physicalSize = const Size(1366, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpAndOpen(tester, previouslyTrusted: false);

    final dialog = tester.widget<AlertDialog>(find.byType(AlertDialog));
    expect(dialog.constraints?.maxWidth, AppSizes.dialogMaxWidth);
  });

  testWidgets(
    'a legacy-pin re-confirmation says the server was trusted before (M1)',
    (tester) async {
      // Telling the user "you're connecting for the first time" on a server
      // the app has connected to many times would suppress exactly the
      // suspicion an MITM wants suppressed (security audit M1 on the
      // dartssh2 3.x migration).
      final l10n = await loadEn();
      await pumpAndOpen(tester, previouslyTrusted: true);
      expect(find.text(l10n.hostKeyBodyRepin('203.0.113.5')), findsOneWidget);
      expect(find.text(l10n.hostKeyBody('203.0.113.5')), findsNothing);
    },
  );

  testWidgets('replacement dialog compares both fingerprints explicitly', (
    tester,
  ) async {
    final replacement = fingerprint.copyWith(
      fingerprint: 'NewKeyGh01234567890123456789012345678901+/x',
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: lightTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showHostKeyReplacementDialog(
              context,
              current: fingerprint,
              replacement: replacement,
            ),
            child: const Text('replace'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('replace'));
    await tester.pumpAndSettle();

    expect(find.text('Currently trusted'), findsOneWidget);
    expect(find.text('New fingerprint'), findsOneWidget);
    expect(
      find.text('SHA256:${fingerprint.fingerprint}'),
      findsOneWidget,
    );
    expect(
      find.text('SHA256:${replacement.fingerprint}'),
      findsOneWidget,
    );
  });
}
