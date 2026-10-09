import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

/// Outcome of one system authentication attempt.
enum DeviceAuthOutcome {
  /// The user passed the device authentication.
  passed,

  /// The user failed or dismissed the prompt, or the auth UI errored.
  /// (In local_auth 3.x a user cancel throws `LocalAuthException`; it maps
  /// here, not to a `false` return.)
  failed,

  /// The device has no unlock method enrolled — the one documented
  /// fail-open case (both platforms map their "no credentials" errors to
  /// `LocalAuthExceptionCode.noCredentialsSet`).
  noCredentials,
}

/// Thin wrapper over the `local_auth` plugin.
///
/// The app lock reuses the device's own unlock (biometrics with fallback to
/// the device PIN/passcode); this service only answers "is a device unlock
/// enrolled" and "did the user pass it". Plugin failures map to `false` so
/// the callers never crash on an auth-UI problem.
class DeviceAuthService {
  /// Creates the service; [auth] is injectable for tests.
  DeviceAuthService({LocalAuthentication? auth})
    : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  /// True when the device can authenticate: biometrics enrolled or a device
  /// credential (PIN/pattern/passcode) is set.
  Future<bool> isAvailable() async {
    try {
      return await _auth.isDeviceSupported();
    } on Exception {
      return false;
    }
  }

  /// Shows the system authentication prompt. [reason] is the localized
  /// message shown by the system UI. Only [DeviceAuthOutcome.noCredentials]
  /// distinguishes "nothing enrolled" from every other non-pass: transient
  /// plugin errors must read as a failed attempt, never as fail-open.
  Future<DeviceAuthOutcome> authenticate(String reason) async {
    try {
      final passed = await _auth.authenticate(
        localizedReason: reason,
        // Keep the auth session alive across the backgrounding the prompt
        // itself causes on Android.
        persistAcrossBackgrounding: true,
      );
      return passed ? DeviceAuthOutcome.passed : DeviceAuthOutcome.failed;
    } on LocalAuthException catch (error) {
      return error.code == LocalAuthExceptionCode.noCredentialsSet
          ? DeviceAuthOutcome.noCredentials
          : DeviceAuthOutcome.failed;
    } on Exception {
      return DeviceAuthOutcome.failed;
    }
  }
}

/// Provides the [DeviceAuthService].
final Provider<DeviceAuthService> deviceAuthServiceProvider =
    Provider<DeviceAuthService>((ref) => DeviceAuthService());

/// Whether a device unlock method is currently available. autoDispose so a
/// fresh value is probed every time the Settings screen subscribes.
final FutureProvider<bool> deviceAuthAvailableProvider =
    FutureProvider.autoDispose<bool>(
      (ref) => ref.watch(deviceAuthServiceProvider).isAvailable(),
    );
