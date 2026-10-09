import 'dart:async';

import 'package:fav/features/settings/application/app_lock_controller.dart';
import 'package:fav/features/settings/application/preferences_controller.dart';
import 'package:fav/features/settings/data/device_auth_service.dart';
import 'package:fav/features/settings/domain/user_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_device_auth_service.dart';
import '../../support/fake_preferences_repository.dart';

void main() {
  ProviderContainer createContainer({
    required bool lockEnabled,
    required FakeDeviceAuthService auth,
  }) {
    final container = ProviderContainer(
      overrides: [
        preferencesRepositoryProvider.overrideWithValue(
          FakePreferencesRepository(
            UserPreferences.defaults.copyWith(appLockEnabled: lockEnabled),
          ),
        ),
        deviceAuthServiceProvider.overrideWithValue(auth),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('starts unlocked when the preference is off', () {
    final container = createContainer(
      lockEnabled: false,
      auth: FakeDeviceAuthService(),
    );
    expect(container.read(appLockControllerProvider), AppLockState.unlocked);
  });

  test('starts locked when the preference is on', () {
    final container = createContainer(
      lockEnabled: true,
      auth: FakeDeviceAuthService(),
    );
    expect(container.read(appLockControllerProvider), AppLockState.locked);
  });

  test('unlock succeeds and unlocks', () async {
    final auth = FakeDeviceAuthService();
    final container = createContainer(lockEnabled: true, auth: auth);
    await container.read(appLockControllerProvider.notifier).unlock('reason');
    expect(container.read(appLockControllerProvider), AppLockState.unlocked);
    expect(auth.authenticateCalls, 1);
  });

  test('unlock failure stays locked', () async {
    final auth = FakeDeviceAuthService(outcome: DeviceAuthOutcome.failed);
    final container = createContainer(lockEnabled: true, auth: auth);
    await container.read(appLockControllerProvider.notifier).unlock('reason');
    expect(container.read(appLockControllerProvider), AppLockState.locked);
  });

  test(
    'unlock fails open only when the device reports no credentials',
    () async {
      // The documented fail-open case: the prompt itself reports that no
      // device unlock is enrolled. A transient plugin error must NOT unlock
      // (it maps to failed, covered by the test above).
      final auth = FakeDeviceAuthService(
        outcome: DeviceAuthOutcome.noCredentials,
      );
      final container = createContainer(lockEnabled: true, auth: auth);
      await container.read(appLockControllerProvider.notifier).unlock('reason');
      expect(container.read(appLockControllerProvider), AppLockState.unlocked);
      expect(auth.authenticateCalls, 1);
    },
  );

  test('unlock lands back on locked when the service throws', () async {
    // Even an escaping Error must not strand the state on `unlocking`,
    // which would leave the retry button disabled forever.
    final auth = FakeDeviceAuthService()..thrown = StateError('boom');
    final container = createContainer(lockEnabled: true, auth: auth);
    final notifier = container.read(appLockControllerProvider.notifier);
    await expectLater(notifier.unlock('reason'), throwsStateError);
    expect(container.read(appLockControllerProvider), AppLockState.locked);
  });

  test('a second unlock while one is in flight is ignored', () async {
    final auth = FakeDeviceAuthService();
    final hold = Completer<void>();
    auth.hold = hold.future;
    final container = createContainer(lockEnabled: true, auth: auth);
    final notifier = container.read(appLockControllerProvider.notifier);
    final first = notifier.unlock('reason');
    final second = notifier.unlock('reason');
    hold.complete();
    await Future.wait([first, second]);
    expect(auth.authenticateCalls, 1);
    expect(container.read(appLockControllerProvider), AppLockState.unlocked);
  });

  test('unlock is a no-op when already unlocked', () async {
    final auth = FakeDeviceAuthService();
    final container = createContainer(lockEnabled: false, auth: auth);
    await container.read(appLockControllerProvider.notifier).unlock('reason');
    expect(auth.authenticateCalls, 0);
  });

  test('lock re-locks an unlocked app while the preference is on', () async {
    final auth = FakeDeviceAuthService();
    final container = createContainer(lockEnabled: true, auth: auth);
    await container.read(appLockControllerProvider.notifier).unlock('reason');
    container.read(appLockControllerProvider.notifier).lock();
    expect(container.read(appLockControllerProvider), AppLockState.locked);
  });

  test('lock does nothing when the preference is off', () {
    final container = createContainer(
      lockEnabled: false,
      auth: FakeDeviceAuthService(),
    );
    expect(container.read(appLockControllerProvider.notifier).lock(), isFalse);
    expect(container.read(appLockControllerProvider), AppLockState.unlocked);
  });

  test('lock reports whether it actually locked', () async {
    final container = createContainer(
      lockEnabled: true,
      auth: FakeDeviceAuthService(),
    );
    final notifier = container.read(appLockControllerProvider.notifier);
    // Already locked at start: nothing to do.
    expect(notifier.lock(), isFalse);
    await notifier.unlock('reason');
    expect(notifier.lock(), isTrue);
  });
}
