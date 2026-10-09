import 'package:fav/features/settings/application/preferences_controller.dart';
import 'package:fav/features/settings/data/device_auth_service.dart';
import 'package:fav/features/settings/domain/app_lock_timeout.dart';
import 'package:fav/features/settings/domain/user_preferences.dart';
import 'package:fav/features/settings/presentation/app_lock_gate.dart';
import 'package:fav/l10n/app_localizations.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PredictiveBackEvent;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../support/fake_device_auth_service.dart';
import '../../support/fake_preferences_repository.dart';

void main() {
  Widget buildApp({
    required bool lockEnabled,
    required FakeDeviceAuthService auth,
    Widget home = const Text('CONTENT'),
    GlobalKey<ScaffoldMessengerState>? messengerKey,
    AppLockTimeout timeout = AppLockTimeout.oneMinute,
    DateTime Function()? now,
  }) {
    return ProviderScope(
      overrides: [
        preferencesRepositoryProvider.overrideWithValue(
          FakePreferencesRepository(
            UserPreferences.defaults.copyWith(
              appLockEnabled: lockEnabled,
              appLockTimeout: timeout,
            ),
          ),
        ),
        deviceAuthServiceProvider.overrideWithValue(auth),
      ],
      child: MaterialApp(
        scaffoldMessengerKey: messengerKey,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) =>
            AppLockGate(now: now, child: child ?? const SizedBox.shrink()),
        home: home,
      ),
    );
  }

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    // Later tests assume a foreground app. Step back to `resumed` through
    // legal adjacent transitions only — a jump like paused → resumed
    // asserts inside any AppLifecycleListener in the tree.
    final binding = TestWidgetsFlutterBinding.instance;
    var state = binding.lifecycleState;
    while (state != null && state != AppLifecycleState.resumed) {
      state = switch (state) {
        AppLifecycleState.paused => AppLifecycleState.hidden,
        AppLifecycleState.hidden => AppLifecycleState.inactive,
        _ => AppLifecycleState.resumed,
      };
      binding.handleAppLifecycleStateChanged(state);
    }
  });

  testWidgets('desktop waits for the configured grace period', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    var now = DateTime(2026);
    final auth = FakeDeviceAuthService();
    await tester.pumpWidget(
      buildApp(lockEnabled: true, auth: auth, now: () => now),
    );
    await tester.pumpAndSettle();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    now = now.add(const Duration(seconds: 59));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(find.text('CONTENT'), findsOneWidget);
    expect(auth.authenticateCalls, 1);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('desktop locks after the configured grace period', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    var now = DateTime(2026);
    final auth = FakeDeviceAuthService();
    await tester.pumpWidget(
      buildApp(lockEnabled: true, auth: auth, now: () => now),
    );
    await tester.pumpAndSettle();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    now = now.add(const Duration(seconds: 61));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(find.text('CONTENT'), findsOneWidget);
    expect(auth.authenticateCalls, 2);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('desktop only-on-launch never re-locks on focus loss', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final auth = FakeDeviceAuthService();
    await tester.pumpWidget(
      buildApp(
        lockEnabled: true,
        auth: auth,
        timeout: AppLockTimeout.onlyOnLaunch,
        now: () => DateTime(2026),
      ),
    );
    await tester.pumpAndSettle();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump(const Duration(minutes: 10));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(find.text('CONTENT'), findsOneWidget);
    expect(auth.authenticateCalls, 1);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('shows the content untouched when the lock is off', (
    tester,
  ) async {
    final auth = FakeDeviceAuthService();
    await tester.pumpWidget(buildApp(lockEnabled: false, auth: auth));
    await tester.pumpAndSettle();
    expect(find.text('CONTENT'), findsOneWidget);
    expect(auth.authenticateCalls, 0);
  });

  testWidgets('auto-prompts on launch and unlocks on success', (tester) async {
    final auth = FakeDeviceAuthService();
    await tester.pumpWidget(buildApp(lockEnabled: true, auth: auth));
    expect(find.text('CONTENT'), findsNothing);
    await tester.pumpAndSettle();
    expect(find.text('CONTENT'), findsOneWidget);
    expect(auth.authenticateCalls, 1);
  });

  testWidgets('stays locked on failure; the button retries', (tester) async {
    final auth = FakeDeviceAuthService(outcome: DeviceAuthOutcome.failed);
    await tester.pumpWidget(buildApp(lockEnabled: true, auth: auth));
    await tester.pumpAndSettle();
    expect(find.text('CONTENT'), findsNothing);
    expect(auth.authenticateCalls, 1);
    auth.outcome = DeviceAuthOutcome.passed;
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(find.text('CONTENT'), findsOneWidget);
    expect(auth.authenticateCalls, 2);
  });

  testWidgets('fails open when the device reports no credentials', (
    tester,
  ) async {
    final auth = FakeDeviceAuthService(
      outcome: DeviceAuthOutcome.noCredentials,
    );
    await tester.pumpWidget(buildApp(lockEnabled: true, auth: auth));
    await tester.pumpAndSettle();
    expect(find.text('CONTENT'), findsOneWidget);
    expect(auth.authenticateCalls, 1);
  });

  testWidgets('the shield covers without unmounting the app subtree', (
    tester,
  ) async {
    // Replacing the child would tear down the Router — killing dialogs,
    // shell sessions and autoDispose controllers — on every transient
    // `inactive` (notification banner, permission dialog, the prompt
    // itself). The child's state must survive a shield round trip.
    final auth = FakeDeviceAuthService();
    await tester.pumpWidget(
      buildApp(lockEnabled: true, auth: auth, home: const _CounterProbe()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('COUNT:0'));
    await tester.pump();
    expect(find.text('COUNT:1'), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    // Covered: nothing of the content is on stage.
    expect(find.text('COUNT:1'), findsNothing);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    // Same state object, not a rebuilt-from-scratch subtree.
    expect(find.text('COUNT:1'), findsOneWidget);
    expect(auth.authenticateCalls, 1);
  });

  testWidgets('re-locks after the grace period and re-prompts on return', (
    tester,
  ) async {
    var now = DateTime(2026);
    final auth = FakeDeviceAuthService();
    await tester.pumpWidget(
      buildApp(lockEnabled: true, auth: auth, now: () => now),
    );
    await tester.pumpAndSettle();
    expect(find.text('CONTENT'), findsOneWidget);

    // Real backgrounding order: inactive (the last frame still rendered —
    // what the OS snapshot captures) → hidden → paused (frames disabled).
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(find.text('CONTENT'), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    now = now.add(const Duration(seconds: 61));

    // Foregrounding walks the same states back in legal order.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('CONTENT'), findsOneWidget);
    expect(auth.authenticateCalls, 2);
  });

  testWidgets('a snackbar fired while locked stays off the lock screen', (
    tester,
  ) async {
    // The app content keeps running behind the lock (by design), so a slow
    // operation can fire its snackbar after the user locked the app. It
    // must not surface over the lock screen (verify pass NEW-1).
    final auth = FakeDeviceAuthService(outcome: DeviceAuthOutcome.failed);
    final messengerKey = GlobalKey<ScaffoldMessengerState>();
    await tester.pumpWidget(
      buildApp(
        lockEnabled: true,
        auth: auth,
        home: const Scaffold(body: Text('CONTENT')),
        messengerKey: messengerKey,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('CONTENT'), findsNothing); // locked

    messengerKey.currentState!.showSnackBar(
      const SnackBar(content: Text('LEAK')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('LEAK'), findsNothing);

    messengerKey.currentState!.clearSnackBars();
    await tester.pumpAndSettle();
  });

  testWidgets('the back button does not drive the covered router', (
    tester,
  ) async {
    // The Router stays mounted (never unmounted) while covered, and the
    // back-button dispatcher is a binding observer, not a widget — the
    // gate must swallow the press while covered (verify pass NEW-2).
    // MaterialApp.router like production: the Router registers its
    // back-button observer AFTER the gate (it is the builder's child), so
    // the gate gets first refusal — home-mode MaterialApp would not
    // reproduce this ordering.
    final auth = FakeDeviceAuthService();
    final router = GoRouter(
      routes: [GoRoute(path: '/', builder: (_, _) => const _PushProbe())],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          preferencesRepositoryProvider.overrideWithValue(
            FakePreferencesRepository(
              UserPreferences.defaults.copyWith(appLockEnabled: true),
            ),
          ),
          deviceAuthServiceProvider.overrideWithValue(auth),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) =>
              AppLockGate(child: child ?? const SizedBox.shrink()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('PUSH'));
    await tester.pumpAndSettle();
    expect(find.text('PAGE2'), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.binding.handlePopRoute(); // Android back while covered

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    // Unlocked back onto the same screen the user left.
    expect(find.text('PAGE2'), findsOneWidget);
  });

  testWidgets('the predictive-back gesture is claimed while covered', (
    tester,
  ) async {
    // Android 15+ predictive back bypasses didPopRoute: the dispatcher
    // polls handleStartBackGesture and only falls back to a plain pop when
    // no observer claims the gesture. While covered the gate must claim
    // and drop it, or the route transition's own detector drives the
    // hidden Router (verify-pass LOW-4).
    final auth = FakeDeviceAuthService(outcome: DeviceAuthOutcome.failed);
    await tester.pumpWidget(buildApp(lockEnabled: true, auth: auth));
    await tester.pumpAndSettle();
    expect(find.text('CONTENT'), findsNothing); // locked → covered

    final observer =
        tester.state(find.byType(AppLockGate)) as WidgetsBindingObserver;
    final event = PredictiveBackEvent.fromMap(const {
      'touchOffset': null,
      'progress': 0.0,
      'swipeEdge': 0,
    });
    expect(observer.handleStartBackGesture(event), isTrue);

    auth.outcome = DeviceAuthOutcome.passed;
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(find.text('CONTENT'), findsOneWidget); // unlocked → uncovered
    expect(observer.handleStartBackGesture(event), isFalse);
  });

  testWidgets('inactive shields the content without a new unlock', (
    tester,
  ) async {
    final auth = FakeDeviceAuthService();
    await tester.pumpWidget(buildApp(lockEnabled: true, auth: auth));
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    // Shielded (snapshot covered), but not locked: no unlock button.
    expect(find.text('CONTENT'), findsNothing);
    expect(find.byType(FilledButton), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('CONTENT'), findsOneWidget);
    expect(auth.authenticateCalls, 1);
  });

  testWidgets('no shield when the app lock is off', (tester) async {
    final auth = FakeDeviceAuthService();
    await tester.pumpWidget(buildApp(lockEnabled: false, auth: auth));
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(find.text('CONTENT'), findsOneWidget);
  });

  testWidgets('a canceled prompt does not re-prompt on resume', (
    tester,
  ) async {
    final auth = FakeDeviceAuthService(outcome: DeviceAuthOutcome.failed);
    await tester.pumpWidget(buildApp(lockEnabled: true, auth: auth));
    await tester.pumpAndSettle();
    expect(auth.authenticateCalls, 1);
    // The system prompt made the app inactive; canceling returns to resumed.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    // Still locked, and no auto re-prompt loop — the button is the retry.
    expect(find.text('CONTENT'), findsNothing);
    expect(find.byType(FilledButton), findsOneWidget);
    expect(auth.authenticateCalls, 1);
  });
}

// (Placed above the probes so the test list stays together.)
class _PushProbe extends StatelessWidget {
  const _PushProbe();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: TextButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('PAGE2')),
            ),
          ),
          child: const Text('PUSH'),
        ),
      ),
    );
  }
}

class _CounterProbe extends StatefulWidget {
  const _CounterProbe();

  @override
  State<_CounterProbe> createState() => _CounterProbeState();
}

class _CounterProbeState extends State<_CounterProbe> {
  int count = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: TextButton(
          onPressed: () => setState(() => count++),
          child: Text('COUNT:$count'),
        ),
      ),
    );
  }
}
