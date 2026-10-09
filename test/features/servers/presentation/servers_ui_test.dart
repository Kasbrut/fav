import 'package:fav/app.dart';
import 'package:fav/core/errors/app_exception.dart';
import 'package:fav/core/persistence/secure_store.dart';
import 'package:fav/core/widgets/app_search_field.dart';
import 'package:fav/core/widgets/app_text_field.dart';
import 'package:fav/features/install/application/run_recovery_provider.dart';
import 'package:fav/features/install/data/keys/ssh_key_repository.dart';
import 'package:fav/features/install/data/scripts/script_integrity.dart';
import 'package:fav/features/install/data/ssh/dart_ssh_client.dart';
import 'package:fav/features/install/data/ssh/host_key_store.dart';
import 'package:fav/features/install/domain/install_run.dart';
import 'package:fav/features/servers/data/hive_server_repository.dart';
import 'package:fav/features/servers/data/server_probe.dart';
import 'package:fav/features/settings/application/preferences_controller.dart';
import 'package:fav/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_preferences_repository.dart';
import '../../../support/in_memory_secure_store.dart';
import '../../../support/server_fakes.dart';

/// A minimal interrupted run targeting [serverId], for banner tests.
InstallRun _runFor(String serverId) => InstallRun(
  runId: 'run-$serverId',
  serverId: serverId,
  status: RunStatus.running,
  steps: const [],
  scriptWasModified: false,
  startedAt: DateTime(2026, 5, 18),
);

/// Widget tests for the servers UI: list, add form and detail navigation.
void main() {
  Future<AppLocalizations> loadEn() {
    return AppLocalizations.delegate.load(const Locale('en'));
  }

  Future<void> pumpApp(
    WidgetTester tester,
    FakeServerRepository repository, {
    StubSshClient? sshClient,
    StubServerProbe? probe,
    List<Override> extraOverrides = const [],
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        // Match production (main.dart): disable Riverpod 3 auto-retry so a
        // failing provider settles into a terminal state instead of looping
        // (which would hang pumpAndSettle).
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
          if (sshClient != null)
            sshClientFactoryProvider.overrideWithValue(() => sshClient),
          if (probe != null) serverProbeProvider.overrideWithValue(probe),
          ...extraOverrides,
        ],
        child: const WireguardProvisionerApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows the empty state with a first-run Add a server CTA', (
    tester,
  ) async {
    final l10n = await loadEn();
    await pumpApp(tester, FakeServerRepository());
    expect(find.text(l10n.serverListEmptyTitle), findsOneWidget);

    // The zero-state offers an explicit CTA that opens the add-server form.
    final cta = find.widgetWithText(FilledButton, l10n.actionAddServer);
    expect(cta, findsOneWidget);
    await tester.tap(cta);
    await tester.pumpAndSettle();
    expect(find.text(l10n.fieldServerName.toUpperCase()), findsOneWidget);
  });

  testWidgets('lists the registered servers', (tester) async {
    final repository = FakeServerRepository();
    await repository.save(testServer(label: 'vps-amsterdam'));
    await pumpApp(tester, repository);
    expect(find.text('vps-amsterdam'), findsOneWidget);
  });

  testWidgets('the card overflow menu opens the teardown modal', (
    tester,
  ) async {
    final l10n = await loadEn();
    final repository = FakeServerRepository();
    await repository.save(testServer(label: 'vps-amsterdam'));
    await pumpApp(tester, repository);

    // Visible, accessible alternative to the swipe gesture.
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.actionRemoveServer));
    await tester.pumpAndSettle();

    // Removal now opens the teardown modal instead of a plain confirm dialog.
    expect(find.text(l10n.teardownTitle), findsOneWidget);
    expect(find.text(l10n.serverRemoveTitle), findsNothing);
  });

  testWidgets('the interrupted-run banner skips runs whose server is gone', (
    tester,
  ) async {
    final l10n = await loadEn();
    final repository = FakeServerRepository();
    await repository.save(testServer(id: 'srv-b', label: 'vps-berlin'));
    await pumpApp(
      tester,
      repository,
      extraOverrides: [
        incompleteRunsProvider.overrideWith(
          (ref) async => [_runFor('srv-missing'), _runFor('srv-b')],
        ),
      ],
    );

    // The orphaned run (its server was removed) must not hide the banner; the
    // resumable run for vps-berlin is offered instead.
    expect(find.text(l10n.incompleteRunTitle), findsOneWidget);
    expect(
      find.widgetWithText(FilledButton, l10n.actionResume),
      findsOneWidget,
    );
    expect(find.textContaining('vps-berlin'), findsWidgets);
  });

  testWidgets('the interrupted-run banner counts additional runs', (
    tester,
  ) async {
    await loadEn();
    final repository = FakeServerRepository();
    await repository.save(testServer(id: 'srv-a', label: 'vps-amsterdam'));
    await repository.save(testServer(id: 'srv-b', label: 'vps-berlin'));
    await pumpApp(
      tester,
      repository,
      extraOverrides: [
        incompleteRunsProvider.overrideWith(
          (ref) async => [_runFor('srv-a'), _runFor('srv-b')],
        ),
      ],
    );

    expect(
      find.textContaining('1 more installation was also interrupted'),
      findsOneWidget,
    );
  });

  testWidgets('the add FAB on a populated list opens the add-server form', (
    tester,
  ) async {
    final l10n = await loadEn();
    final repository = FakeServerRepository();
    await repository.save(testServer(label: 'vps-amsterdam'));
    await pumpApp(tester, repository);

    // Thumb-reachable, labelled add action for the populated list.
    expect(find.byType(FloatingActionButton), findsOneWidget);
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    expect(find.text(l10n.fieldServerName.toUpperCase()), findsOneWidget);
  });

  testWidgets('the add form rejects an empty submission', (tester) async {
    final l10n = await loadEn();
    await pumpApp(tester, FakeServerRepository());
    // Reach the form via the empty-state CTA (no app-bar add icon).
    await tester.tap(find.widgetWithText(FilledButton, l10n.actionAddServer));
    await tester.pumpAndSettle();

    await tester.tap(find.text(l10n.actionConnectInstall));
    await tester.pumpAndSettle();

    expect(find.text(l10n.validationServerName), findsOneWidget);
  });

  testWidgets('adding a server connects, probes and starts install', (
    tester,
  ) async {
    final l10n = await loadEn();
    await pumpApp(
      tester,
      FakeServerRepository(),
      sshClient: StubSshClient(),
      probe: StubServerProbe(metadata: testMetadata()),
      extraOverrides: [
        // Fail integrity fast so the install does not poll indefinitely.
        bootIntegrityProvider.overrideWith(
          (ref) => throw const AppException(ErrorCode.scriptInvalid),
        ),
        // M15-T1: the install controller now creates the app SSH key on
        // every run; provide an in-memory store for the widget test.
        sshKeyRepositoryProvider.overrideWithValue(
          SecureSshKeyRepository(InMemorySecureStore()),
        ),
      ],
    );
    // Reach the form via the empty-state CTA (no app-bar add icon).
    await tester.tap(find.widgetWithText(FilledButton, l10n.actionAddServer));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(AppTextField, l10n.fieldServerName.toUpperCase()),
      'new-vps',
    );
    await tester.enterText(
      find.bySemanticsLabel(l10n.fieldHost),
      '203.0.113.9',
    );
    await tester.enterText(
      find.widgetWithText(AppTextField, l10n.fieldUsername.toUpperCase()),
      'deploy',
    );
    await tester.enterText(
      find.widgetWithText(AppTextField, l10n.fieldPassword.toUpperCase()),
      'password',
    );
    await tester.tap(find.text(l10n.actionConnectInstall));
    await tester.pumpAndSettle();

    expect(find.text(l10n.installProgressTitle), findsOneWidget);
  });

  testWidgets('tapping a server opens its detail screen', (tester) async {
    final l10n = await loadEn();
    final repository = FakeServerRepository();
    await repository.save(testServer(label: 'vps-amsterdam'));
    await pumpApp(tester, repository);

    await tester.tap(find.text('vps-amsterdam'));
    await tester.pumpAndSettle();

    expect(
      find.text(l10n.detailSectionSystem.toUpperCase()),
      findsOneWidget,
    );
  });

  testWidgets('re-probing a server reports success', (tester) async {
    // Tall surface: the detail screen grew an Install WireGuard CTA above
    // the re-probe button, which would otherwise sit below the fold.
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final l10n = await loadEn();
    final repository = FakeServerRepository();
    await repository.save(testServer(label: 'vps-amsterdam'));
    await pumpApp(
      tester,
      repository,
      sshClient: StubSshClient(),
      probe: StubServerProbe(metadata: testMetadata()),
    );
    await tester.tap(find.text('vps-amsterdam'));
    await tester.pumpAndSettle();

    await tester.tap(find.text(l10n.actionReprobe));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'password');
    await tester.tap(find.text(l10n.actionConfirm));
    await tester.pumpAndSettle();

    expect(find.text(l10n.reprobeSuccess), findsOneWidget);
  });

  testWidgets('the search field filters the server list', (tester) async {
    final repository = FakeServerRepository();
    await repository.save(testServer(label: 'vps-amsterdam'));
    await repository.save(testServer(id: 'srv-2', label: 'home-lab'));
    await pumpApp(tester, repository);

    expect(find.text('vps-amsterdam'), findsOneWidget);
    expect(find.text('home-lab'), findsOneWidget);

    await tester.enterText(find.byType(AppSearchField), 'amsterdam');
    await tester.pumpAndSettle();

    expect(find.text('vps-amsterdam'), findsOneWidget);
    expect(find.text('home-lab'), findsNothing);
  });

  testWidgets('the search field shows an empty-result message', (
    tester,
  ) async {
    final l10n = await loadEn();
    final repository = FakeServerRepository();
    await repository.save(testServer(label: 'vps-amsterdam'));
    await pumpApp(tester, repository);

    await tester.enterText(find.byType(AppSearchField), 'no-such-server');
    await tester.pumpAndSettle();

    expect(find.text(l10n.serverSearchEmpty), findsOneWidget);
  });
}
