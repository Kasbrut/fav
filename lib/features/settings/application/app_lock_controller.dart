import 'package:fav/features/settings/application/preferences_controller.dart';
import 'package:fav/features/settings/data/device_auth_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Lock state of the whole app UI (spec: app-lock design, 2026-08-20).
enum AppLockState {
  /// Content hidden behind the lock screen.
  locked,

  /// The system authentication prompt is showing.
  unlocking,

  /// Content visible.
  unlocked,
}

/// Owns the app-lock state machine.
///
/// Starts locked iff the preference is enabled. Lifecycle handlers call
/// [lock]; the lock screen calls [unlock]. Fails open when no device unlock
/// is available: the lock protects exactly as much as the device does.
class AppLockController extends Notifier<AppLockState> {
  @override
  AppLockState build() {
    // read, not watch: preference changes (or unrelated preference writes)
    // must never rebuild — and thereby re-lock — a running session.
    final enabled = ref.read(preferencesControllerProvider).appLockEnabled;
    return enabled ? AppLockState.locked : AppLockState.unlocked;
  }

  /// Re-locks the UI (called on lifecycle hidden/paused). Ignored while the
  /// auth prompt is up — the prompt itself backgrounds the app on Android —
  /// and when the preference is off. Returns true only when this call
  /// actually locked, so the gate can arm a fresh auto-prompt per lock
  /// episode (and never after a canceled prompt).
  bool lock() {
    if (state != AppLockState.unlocked) return false;
    if (!ref.read(preferencesControllerProvider).appLockEnabled) return false;
    state = AppLockState.locked;
    return true;
  }

  /// Runs the system prompt with the localized [reason]. No-op unless
  /// currently locked (the resumed event after a successful prompt must not
  /// re-prompt). A device with no unlock enrolled unlocks (fail open); any
  /// other non-pass — including transient plugin errors — stays locked.
  Future<void> unlock(String reason) async {
    if (state != AppLockState.locked) return;
    // Set synchronously so an overlapping call (auto-prompt racing an
    // impatient button tap) cannot start a second system prompt.
    state = AppLockState.unlocking;
    var next = AppLockState.locked;
    try {
      final outcome = await ref
          .read(deviceAuthServiceProvider)
          .authenticate(reason);
      // Exhaustive on purpose: a future outcome value must force a
      // decision here, never default to an unlock (verify pass NEW-3).
      next = switch (outcome) {
        DeviceAuthOutcome.passed ||
        DeviceAuthOutcome.noCredentials => AppLockState.unlocked,
        DeviceAuthOutcome.failed => AppLockState.locked,
      };
    } finally {
      // Even an escaping Error must land on a live state — a dead-end
      // `unlocking` would leave the retry button disabled forever.
      state = next;
    }
  }
}

/// Provides the [AppLockController].
final NotifierProvider<AppLockController, AppLockState>
appLockControllerProvider = NotifierProvider<AppLockController, AppLockState>(
  AppLockController.new,
);
