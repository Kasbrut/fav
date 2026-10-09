import 'dart:async';

import 'package:fav/features/settings/application/preferences_controller.dart';
import 'package:fav/features/settings/data/device_auth_service.dart';
import 'package:fav/features/settings/domain/user_preferences.dart';
import 'package:fav/features/settings/presentation/settings_screen.dart';
import 'package:fav/features/settings/presentation/widgets/about_section.dart';
import 'package:fav/features/settings/presentation/widgets/app_lock_section.dart';
import 'package:fav/features/settings/presentation/widgets/danger_zone_section.dart';
import 'package:fav/features/settings/presentation/widgets/diagnostic_export_section.dart';
import 'package:fav/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_device_auth_service.dart';
import '../../support/fake_preferences_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    // Stub package_info_plus so AboutSection's FutureBuilder resolves
    // immediately instead of hanging on an unanswered plugin channel call.
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/package_info'),
      (call) async {
        if (call.method == 'getAll') {
          return <String, dynamic>{
            'appName': 'FAV',
            'packageName': 'com.kasbrut.fav',
            'version': '1.0.0',
            'buildNumber': '1',
            'buildSignature': '',
            'installerStore': null,
          };
        }
        return null;
      },
    );
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/package_info'),
      null,
    );
  });

  testWidgets('renders the 5 sections', (tester) async {
    // Tall viewport so all sections lay out without scrolling.
    tester.view.physicalSize = const Size(800, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          preferencesRepositoryProvider.overrideWithValue(
            FakePreferencesRepository(),
          ),
        ],
        child: const MaterialApp(
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: SettingsScreen(),
        ),
      ),
    );
    // Three explicit pumps instead of pumpAndSettle to avoid hanging on
    // the AboutSection's PackageInfo Future (plugin channel unavailable
    // in widget tests).
    await tester.pump();
    await tester.pump();
    await tester.pump();

    // 1 SectionRadioCard widget (ThemeMode); language is now a summary row.
    expect(
      find.byWidgetPredicate(
        (w) => w.runtimeType.toString().startsWith('SectionRadioCard<'),
      ),
      findsOneWidget,
    );
    // The language summary row shows "Automatic" by default (locale = system),
    // distinct from the theme radio's "Follow system" option.
    expect(find.text('Automatic'), findsOneWidget);
    expect(find.byType(AppLockSection), findsOneWidget);
    expect(find.byType(AboutSection), findsOneWidget);
    expect(find.byType(DiagnosticExportSection), findsOneWidget);
    expect(find.byType(DangerZoneSection), findsOneWidget);
  });

  Future<FakePreferencesRepository> pumpSettings(
    WidgetTester tester, {
    required FakeDeviceAuthService auth,
  }) async {
    tester.view.physicalSize = const Size(800, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = FakePreferencesRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          preferencesRepositoryProvider.overrideWithValue(repo),
          deviceAuthServiceProvider.overrideWithValue(auth),
        ],
        child: const MaterialApp(
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: SettingsScreen(),
        ),
      ),
    );
    // Explicit pumps instead of pumpAndSettle (AboutSection PackageInfo).
    await tester.pump();
    await tester.pump();
    await tester.pump();
    return repo;
  }

  testWidgets('app-lock switch is disabled without a device unlock', (
    tester,
  ) async {
    await pumpSettings(tester, auth: FakeDeviceAuthService(available: false));
    final tile = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
    expect(tile.onChanged, isNull);
    expect(
      find.text('Set up a screen lock on this device to use the app lock'),
      findsOneWidget,
    );
  });

  testWidgets('toggling on requires a successful authentication', (
    tester,
  ) async {
    final auth = FakeDeviceAuthService();
    final repo = await pumpSettings(tester, auth: auth);
    await tester.tap(find.byType(SwitchListTile));
    await tester.pump();
    await tester.pump();
    expect(auth.authenticateCalls, 1);
    expect(repo.readSync().appLockEnabled, isTrue);
    final tile = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
    expect(tile.value, isTrue);
  });

  testWidgets('toggle does not move when authentication fails', (
    tester,
  ) async {
    final auth = FakeDeviceAuthService(outcome: DeviceAuthOutcome.failed);
    final repo = await pumpSettings(tester, auth: auth);
    await tester.tap(find.byType(SwitchListTile));
    await tester.pump();
    await tester.pump();
    expect(auth.authenticateCalls, 1);
    expect(repo.readSync().appLockEnabled, isFalse);
    final tile = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
    expect(tile.value, isFalse);
  });

  testWidgets('disabling persists even if the section unmounts mid-prompt', (
    tester,
  ) async {
    // The gate's privacy shield unmounts the whole Settings screen while
    // the system prompt is up. The pending toggle must still complete —
    // otherwise the app lock can never be turned off (audit HIGH-1).
    tester.view.physicalSize = const Size(800, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final auth = FakeDeviceAuthService();
    final hold = Completer<void>();
    auth.hold = hold.future;
    final repo = FakePreferencesRepository(
      UserPreferences.defaults.copyWith(appLockEnabled: true),
    );
    Widget shell(Widget home) => ProviderScope(
      overrides: [
        preferencesRepositoryProvider.overrideWithValue(repo),
        deviceAuthServiceProvider.overrideWithValue(auth),
      ],
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: home,
      ),
    );

    await tester.pumpWidget(shell(const SettingsScreen()));
    await tester.pump();
    await tester.pump();
    await tester.pump();
    await tester.tap(find.byType(SwitchListTile));
    await tester.pump();
    // Unmount the section while the prompt is pending (same ProviderScope
    // element, so the container survives — as it does under the gate).
    await tester.pumpWidget(shell(const SizedBox()));
    hold.complete();
    await tester.pump();
    await tester.pump();
    expect(auth.authenticateCalls, 1);
    expect(repo.readSync().appLockEnabled, isFalse);
  });
}
