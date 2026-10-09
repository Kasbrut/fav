import 'package:fav/app.dart';
import 'package:fav/core/persistence/secure_store.dart';
import 'package:fav/core/widgets/app_text_field.dart';
import 'package:fav/core/widgets/password_strength_bar.dart';
import 'package:fav/features/install/application/install_controller.dart';
import 'package:fav/features/install/data/ssh/host_key_store.dart';
import 'package:fav/features/install/domain/advanced_options.dart';
import 'package:fav/features/install/domain/new_user_spec.dart';
import 'package:fav/features/servers/data/hive_server_repository.dart';
import 'package:fav/features/servers/domain/server.dart';
import 'package:fav/features/settings/application/preferences_controller.dart';
import 'package:fav/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_preferences_repository.dart';
import '../../../support/in_memory_secure_store.dart';
import '../../../support/server_fakes.dart';

/// [InstallController] that records [start] calls instead of provisioning.
class _StubInstallController extends InstallController {
  int startCalls = 0;
  Server? startedServer;
  NewUserSpec? startedNewUser;
  String? startedPassword;
  AdvancedOptions? startedOptions;

  @override
  Future<void> start({
    required Server server,
    required AdvancedOptions options,
    required String sshPassword,
    NewUserSpec? newUser,
  }) async {
    startCalls += 1;
    startedServer = server;
    startedNewUser = newUser;
    startedPassword = sshPassword;
    startedOptions = options;
    state = const InstallPreparing();
  }
}

void main() {
  Future<AppLocalizations> loadEn() {
    return AppLocalizations.delegate.load(const Locale('en'));
  }

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
          ...extraOverrides,
        ],
        child: const WireguardProvisionerApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the card menu offers the install only when not installed', (
    tester,
  ) async {
    final l10n = await loadEn();
    final repository = FakeServerRepository();
    await repository.save(testServer(label: 'bare-vps'));
    await pumpApp(tester, repository);

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    expect(find.text(l10n.actionInstallWireguard), findsOneWidget);
  });

  testWidgets('the card menu hides the install for an installed server', (
    tester,
  ) async {
    final l10n = await loadEn();
    final repository = FakeServerRepository();
    await repository.save(hardenedServerWithAppKey());
    await pumpApp(tester, repository);

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    expect(find.text(l10n.actionInstallWireguard), findsNothing);
    expect(find.text(l10n.actionRemoveServer), findsOneWidget);
  });

  testWidgets('the detail screen leads to the install for a bare server', (
    tester,
  ) async {
    final l10n = await loadEn();
    final repository = FakeServerRepository();
    await repository.save(testServer(label: 'bare-vps'));
    await pumpApp(tester, repository);

    await tester.tap(find.text('bare-vps'));
    await tester.pumpAndSettle();
    final button = find.widgetWithText(
      FilledButton,
      l10n.actionInstallWireguard,
    );
    expect(button, findsOneWidget);

    await tester.tap(button);
    await tester.pumpAndSettle();
    // The install screen for a root login asks for the management user too.
    expect(find.text(l10n.fieldNewUsername.toUpperCase()), findsOneWidget);
    expect(find.text(l10n.fieldPassword.toUpperCase()), findsOneWidget);
  });

  testWidgets('the install screen starts the install with the credentials', (
    tester,
  ) async {
    // Tall surface so the whole form (banner + four fields + CTA) fits
    // without fighting the ListView's lazy building.
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final l10n = await loadEn();
    final repository = FakeServerRepository();
    await repository.save(testServer(label: 'bare-vps'));
    final controller = _StubInstallController();
    await pumpApp(
      tester,
      repository,
      extraOverrides: [
        installControllerProvider.overrideWith(() => controller),
      ],
    );

    await tester.tap(find.text('bare-vps'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(FilledButton, l10n.actionInstallWireguard),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(AppTextField, l10n.fieldNewUsername.toUpperCase()),
      'favops',
    );
    final newPassword = find.widgetWithText(
      AppTextField,
      l10n.fieldNewPassword.toUpperCase(),
    );
    await tester.enterText(newPassword, 'Password1!');
    await tester.pump();
    expect(find.text(l10n.validationNewPassword), findsOneWidget);
    expect(find.byType(PasswordStrengthBar), findsNothing);
    await tester.enterText(newPassword, 'Fv9!lab-Ops-2026');
    await tester.pump();
    expect(find.text(l10n.validationNewPassword), findsNothing);
    expect(find.byType(PasswordStrengthBar), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(
        AppTextField,
        l10n.fieldConfirmPassword.toUpperCase(),
      ),
      'Fv9!lab-Ops-2026',
    );
    await tester.enterText(
      find.widgetWithText(AppTextField, l10n.fieldPassword.toUpperCase()),
      'root-pw',
    );
    final cta = find.widgetWithText(FilledButton, l10n.actionInstallWireguard);
    await tester.tap(cta);
    // A second tap in the same frame must not launch another provisioning.
    await tester.tap(cta);
    // The stub sets InstallPreparing, whose spinner animates forever: plain
    // pumps instead of pumpAndSettle.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(controller.startedServer?.label, 'bare-vps');
    expect(controller.startCalls, 1);
    expect(controller.startedPassword, 'root-pw');
    expect(controller.startedNewUser?.username, 'favops');
  });

  testWidgets('advanced options edited from the install screen are kept', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final l10n = await loadEn();
    final repository = FakeServerRepository();
    await repository.save(testServer(label: 'bare-vps'));
    final controller = _StubInstallController();
    await pumpApp(
      tester,
      repository,
      extraOverrides: [
        installControllerProvider.overrideWith(() => controller),
      ],
    );

    await tester.tap(find.text('bare-vps'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(FilledButton, l10n.actionInstallWireguard),
    );
    await tester.pumpAndSettle();

    // Edit an advanced option, save, and come back: the autoDispose form
    // provider must survive the round trip (it silently reset before).
    await tester.tap(find.text(l10n.actionAdvanced));
    await tester.pumpAndSettle();
    // The advanced form edits values through per-row dialogs.
    await tester.tap(find.text(l10n.fieldWgPort));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '51900');
    await tester.tap(find.text(l10n.actionConfirm));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, l10n.actionSave));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(AppTextField, l10n.fieldNewUsername.toUpperCase()),
      'favops',
    );
    await tester.enterText(
      find.widgetWithText(AppTextField, l10n.fieldNewPassword.toUpperCase()),
      'Fv9!lab-Ops-2026',
    );
    await tester.enterText(
      find.widgetWithText(
        AppTextField,
        l10n.fieldConfirmPassword.toUpperCase(),
      ),
      'Fv9!lab-Ops-2026',
    );
    await tester.enterText(
      find.widgetWithText(AppTextField, l10n.fieldPassword.toUpperCase()),
      'root-pw',
    );
    await tester.tap(
      find.widgetWithText(FilledButton, l10n.actionInstallWireguard),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(controller.startedOptions?.wgPort, 51900);
  });
}
