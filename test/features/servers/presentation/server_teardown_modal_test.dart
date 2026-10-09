import 'package:fav/app.dart';
import 'package:fav/core/errors/app_exception.dart';
import 'package:fav/core/persistence/secure_store.dart';
import 'package:fav/core/theme/app_theme.dart';
import 'package:fav/features/install/data/keys/ssh_key_repository.dart';
import 'package:fav/features/install/data/ssh/host_key_store.dart';
import 'package:fav/features/servers/application/server_teardown_controller.dart';
import 'package:fav/features/servers/data/hive_server_repository.dart';
import 'package:fav/features/servers/domain/server.dart';
import 'package:fav/features/servers/domain/wireguard_installation.dart';
import 'package:fav/features/servers/presentation/widgets/server_teardown_modal.dart';
import 'package:fav/features/settings/application/preferences_controller.dart';
import 'package:fav/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_preferences_repository.dart';
import '../../../support/in_memory_secure_store.dart';
import '../../../support/server_fakes.dart';

/// Stub controller that just holds a fixed state for rendering tests.
class _StubTeardownController extends ServerTeardownController {
  _StubTeardownController(this._initial);
  final TeardownFlowState _initial;
  @override
  TeardownFlowState build() => _initial;
}

void main() {
  Future<AppLocalizations> en() =>
      AppLocalizations.delegate.load(const Locale('en'));

  Future<void> pumpModalHost(
    WidgetTester tester, {
    required Server server,
    required List<Override> overrides,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: MaterialApp(
          theme: lightTheme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => showTeardownModal(context, server),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('idle: a never-hardened server hides the re-open SSH option', (
    tester,
  ) async {
    final l10n = await en();
    await pumpModalHost(
      tester,
      server: testServer(),
      overrides: [
        serverTeardownControllerProvider.overrideWith(
          () => _StubTeardownController(const TeardownIdle()),
        ),
      ],
    );

    expect(find.text(l10n.teardownServicesOption), findsOneWidget);
    // Hardening was never applied: there is nothing to re-open (F8).
    expect(find.text(l10n.teardownReopenOption), findsNothing);
    expect(find.text(l10n.teardownReopenWarning), findsNothing);

    final checkboxes = tester
        .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
        .toList();
    expect(checkboxes, hasLength(1));
    expect(checkboxes.single.value, isFalse);

    // No lockout risk for a plain server (sshKeyId null) → remote disconnect
    // and explicit local-only removal are both available.
    final remove = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, l10n.teardownDisconnectAction),
    );
    expect(remove.onPressed, isNotNull);
    expect(find.text(l10n.teardownRemoveLocallyAction), findsOneWidget);
    expect(find.text(l10n.teardownLockoutWarning), findsNothing);

    await tester.tap(find.text(l10n.teardownRemoveLocallyAction));
    await tester.pumpAndSettle();
    expect(find.text(l10n.serverRemoveTitle), findsOneWidget);
    expect(find.text(l10n.serverRemoveMessage('vps-test')), findsOneWidget);
    await tester.tap(find.text(l10n.actionCancel).last);
    await tester.pumpAndSettle();
    expect(find.text(l10n.teardownTitle), findsOneWidget);
  });

  testWidgets('idle: a root-SSH-disabled server keeps the re-open option', (
    tester,
  ) async {
    // Anti-lockout succeeded but hardening was never applied (the common
    // root-login install): the in-app way to restore root SSH must stay
    // available (security review L4).
    final l10n = await en();
    final server = testServer().copyWith(
      installation: WireguardInstallation(
        interfaceName: 'wg0',
        listenPort: 51820,
        vpnSubnet: '10.13.13.0/24',
        serverPublicKey: 'pub',
        peers: const [],
        hardeningApplied: false,
        rootSshDisabled: true,
        installedAt: DateTime(2026, 8, 19),
      ),
    );
    await pumpModalHost(
      tester,
      server: server,
      overrides: [
        serverTeardownControllerProvider.overrideWith(
          () => _StubTeardownController(const TeardownIdle()),
        ),
      ],
    );

    expect(find.text(l10n.teardownReopenOption), findsOneWidget);
  });

  testWidgets('idle: a hardened server shows both option checkboxes', (
    tester,
  ) async {
    final l10n = await en();
    await pumpModalHost(
      tester,
      server: hardenedServerWithAppKey(ownKeys: const ['ssh-ed25519 AAA k']),
      overrides: [
        serverTeardownControllerProvider.overrideWith(
          () => _StubTeardownController(const TeardownIdle()),
        ),
      ],
    );

    expect(find.text(l10n.teardownServicesOption), findsOneWidget);
    expect(find.text(l10n.teardownReopenOption), findsOneWidget);
    expect(find.text(l10n.teardownReopenWarning), findsOneWidget);

    final checkboxes = tester
        .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
        .toList();
    expect(checkboxes, hasLength(2));
    expect(checkboxes.every((c) => c.value == false), isTrue);
  });

  testWidgets('lockout guard: warns and gates confirm until re-open SSH', (
    tester,
  ) async {
    final l10n = await en();
    await pumpModalHost(
      tester,
      server: hardenedServerWithAppKey(),
      overrides: [
        serverTeardownControllerProvider.overrideWith(
          () => _StubTeardownController(const TeardownIdle()),
        ),
      ],
    );

    // Lockout risk: warning shown, no Remove button, "add key" action instead.
    expect(find.text(l10n.teardownLockoutWarning), findsOneWidget);
    expect(
      find.widgetWithText(FilledButton, l10n.teardownDisconnectAction),
      findsNothing,
    );
    expect(find.text(l10n.teardownAddKeyAction), findsOneWidget);

    // Checking re-open SSH clears the risk and re-enables confirm.
    await tester.tap(find.text(l10n.teardownReopenOption));
    await tester.pumpAndSettle();

    expect(find.text(l10n.teardownLockoutWarning), findsNothing);
    expect(find.text(l10n.teardownAddKeyAction), findsNothing);
    final remove = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, l10n.teardownDisconnectAction),
    );
    expect(remove.onPressed, isNotNull);
    expect(find.text(l10n.teardownRemoveLocallyAction), findsNothing);
  });

  testWidgets('cleanup selection clarifies the outcome and hides local-only', (
    tester,
  ) async {
    final l10n = await en();
    await pumpModalHost(
      tester,
      server: testServer(),
      overrides: [
        serverTeardownControllerProvider.overrideWith(
          () => _StubTeardownController(const TeardownIdle()),
        ),
      ],
    );

    expect(find.text(l10n.teardownDisconnectSummary), findsOneWidget);
    await tester.tap(find.text(l10n.teardownServicesOption));
    await tester.pumpAndSettle();

    expect(find.text(l10n.teardownUninstallSummary), findsOneWidget);
    expect(
      find.widgetWithText(FilledButton, l10n.teardownUninstallAction),
      findsOneWidget,
    );
    expect(find.text(l10n.teardownRemoveLocallyAction), findsNothing);
  });

  testWidgets('failure: shows title, retry and remove-locally actions', (
    tester,
  ) async {
    final l10n = await en();
    await pumpModalHost(
      tester,
      server: testServer(),
      overrides: [
        serverTeardownControllerProvider.overrideWith(
          () => _StubTeardownController(
            const TeardownFailure(AppException(ErrorCode.teardownFailed)),
          ),
        ),
      ],
    );

    expect(find.text(l10n.teardownFailedTitle), findsOneWidget);
    expect(find.text(l10n.teardownRetryAction), findsOneWidget);
    expect(find.text(l10n.teardownRemoveLocallyAction), findsOneWidget);
  });

  // ---------------------------------------------------------------------------
  // Wiring tests: the teardown modal is opened from the server list and detail
  // ---------------------------------------------------------------------------

  Future<void> pumpApp(
    WidgetTester tester,
    FakeServerRepository repository, {
    List<Override> extraOverrides = const [],
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          serverRepositoryProvider.overrideWithValue(repository),
          secureStoreProvider.overrideWithValue(InMemorySecureStore()),
          hostKeyStoreProvider.overrideWithValue(
            HostKeyStore(InMemorySecureStore()),
          ),
          preferencesRepositoryProvider.overrideWithValue(
            FakePreferencesRepository(),
          ),
          sshKeyRepositoryProvider.overrideWithValue(
            SecureSshKeyRepository(InMemorySecureStore()),
          ),
          serverTeardownControllerProvider.overrideWith(
            () => _StubTeardownController(const TeardownIdle()),
          ),
          ...extraOverrides,
        ],
        child: const WireguardProvisionerApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'card overflow remove opens the teardown modal',
    (tester) async {
      final l10n = await en();
      final repository = FakeServerRepository();
      await repository.save(testServer());
      await pumpApp(tester, repository);

      // Open the card's overflow menu and tap Remove server.
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.actionRemoveServer));
      await tester.pumpAndSettle();

      // The teardown modal should now be visible instead of the old dialog.
      expect(find.text(l10n.teardownTitle), findsOneWidget);
      // The old plain confirm dialog should not appear.
      expect(find.text(l10n.serverRemoveTitle), findsNothing);
    },
  );

  testWidgets(
    'swipe-to-dismiss opens teardown modal and does NOT remove the card',
    (tester) async {
      final l10n = await en();
      final server = testServer();
      final repository = FakeServerRepository();
      await repository.save(server);
      await pumpApp(tester, repository);

      // The server card must be visible before swiping.
      expect(find.text(server.label), findsOneWidget);

      // Fling end-to-start to trigger the Dismissible's confirmDismiss.
      await tester.fling(
        find.text(server.label),
        const Offset(-500, 0),
        1000,
      );
      await tester.pumpAndSettle();

      // The teardown modal should have opened.
      expect(find.text(l10n.teardownTitle), findsOneWidget);

      // The card must still be present — confirmDismiss returns false, so
      // the Dismissible never auto-removes it.
      expect(find.text(server.label), findsOneWidget);
    },
  );
}
