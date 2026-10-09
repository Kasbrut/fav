import 'package:fav/core/persistence/secure_store.dart';
import 'package:fav/core/theme/app_theme.dart';
import 'package:fav/features/install/data/ssh/host_key_store.dart';
import 'package:fav/features/install/domain/ssh_client.dart';
import 'package:fav/features/servers/domain/host_key_fingerprint.dart';
import 'package:fav/features/servers/presentation/widgets/host_key_dialog.dart';
import 'package:fav/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/in_memory_secure_store.dart';

void main() {
  final fingerprint = HostKeyFingerprint(
    host: '203.0.113.5',
    port: 22,
    keyType: 'ssh-ed25519',
    hashAlgorithm: 'sha256',
    fingerprint: 'AbCdEf',
    pinnedAt: DateTime(2026, 8, 20),
  );

  Future<AppLocalizations> loadEn() =>
      AppLocalizations.delegate.load(const Locale('en'));

  Future<(InMemorySecureStore, Future<bool> Function())> pumpHarness(
    WidgetTester tester,
    HostKeyUnknownException pending,
  ) async {
    final store = InMemorySecureStore();
    late Future<bool> Function() invoke;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [secureStoreProvider.overrideWithValue(store)],
        child: MaterialApp(
          theme: lightTheme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Consumer(
            builder: (context, ref, _) {
              invoke = () => confirmPendingHostKey(context, ref, pending);
              return const Scaffold(body: Text('host'));
            },
          ),
        ),
      ),
    );
    return (store, invoke);
  }

  testWidgets('confirming pins the key and asks for a retry', (tester) async {
    final l10n = await loadEn();
    final (store, invoke) = await pumpHarness(
      tester,
      HostKeyUnknownException(fingerprint, previouslyTrusted: true),
    );

    final result = invoke();
    await tester.pumpAndSettle();
    // The legacy-pin copy, not the first-connection one (audit M1/M3).
    expect(find.text(l10n.hostKeyBodyRepin('203.0.113.5')), findsOneWidget);

    await tester.tap(find.text(l10n.actionConnect));
    await tester.pumpAndSettle();

    expect(await result, isTrue);
    final pinned = await HostKeyStore(store).lookup('203.0.113.5', 22);
    expect(pinned?.fingerprint, 'AbCdEf');
    expect(pinned?.hashAlgorithm, 'sha256');
  });

  testWidgets('declining pins nothing and skips the retry', (tester) async {
    final l10n = await loadEn();
    final (store, invoke) = await pumpHarness(
      tester,
      HostKeyUnknownException(fingerprint),
    );

    final result = invoke();
    await tester.pumpAndSettle();
    expect(find.text(l10n.hostKeyBody('203.0.113.5')), findsOneWidget);

    await tester.tap(find.text(l10n.actionCancel));
    await tester.pumpAndSettle();

    expect(await result, isFalse);
    expect(await HostKeyStore(store).lookup('203.0.113.5', 22), isNull);
  });
}
