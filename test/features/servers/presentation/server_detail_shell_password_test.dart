import 'package:fav/core/crypto/ed25519_keypair.dart';
import 'package:fav/core/persistence/secure_store.dart';
import 'package:fav/core/router/app_router.dart';
import 'package:fav/core/theme/app_theme.dart';
import 'package:fav/features/install/data/keys/ssh_key_repository.dart';
import 'package:fav/features/install/data/ssh/dart_ssh_client.dart';
import 'package:fav/features/peers/data/hive_peer_repository.dart';
import 'package:fav/features/servers/data/hive_server_repository.dart';
import 'package:fav/features/servers/presentation/server_detail_screen.dart';
import 'package:fav/features/shell/application/pending_shell_password.dart';
import 'package:fav/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../support/fake_ssh_key_repository.dart';
import '../../../support/in_memory_secure_store.dart';
import '../../../support/recording_ssh_client.dart';
import '../../../support/server_fakes.dart';
import '../../../support/static_peer_repository.dart';

void main() {
  testWidgets('an unconsumed shell password is drained on return', (
    tester,
  ) async {
    // The holder is root-scoped and put() happens before the push: if the
    // shell route never consumes the entry, the cleartext password would
    // sit in memory for the process lifetime. Returning from the route
    // must drain it (verify-pass LOW-3).
    final server = testServer(); // password-auth: no sshKeyId
    final servers = FakeServerRepository();
    await servers.save(server);
    final passwords = PendingShellPasswords();

    // A shell route that deliberately does NOT take() the password —
    // the abandoned-entry case.
    final router = GoRouter(
      initialLocation: '/detail',
      routes: [
        GoRoute(
          path: '/detail',
          builder: (_, _) => ServerDetailScreen(serverId: server.id),
        ),
        GoRoute(
          path: sshShellRoute,
          builder: (_, _) => const Scaffold(body: Text('SHELL')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          secureStoreProvider.overrideWithValue(InMemorySecureStore()),
          serverRepositoryProvider.overrideWithValue(servers),
          peerRepositoryProvider.overrideWithValue(StaticPeerRepository([])),
          sshClientFactoryProvider.overrideWithValue(RecordingSshClient.new),
          sshKeyRepositoryProvider.overrideWithValue(
            FakeSshKeyRepository(await Ed25519KeyPair.generate()),
          ),
          pendingShellPasswordsProvider.overrideWithValue(passwords),
        ],
        child: MaterialApp.router(
          theme: lightTheme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await tester.tap(find.byIcon(Icons.terminal));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'pw-secret');
    await tester.tap(find.text(l10n.actionConfirm));
    await tester.pumpAndSettle();
    expect(find.text('SHELL'), findsOneWidget);

    // Return to the detail screen without the password ever being taken.
    router.pop();
    await tester.pumpAndSettle();
    expect(passwords.take(server.id), isNull);
  });
}
