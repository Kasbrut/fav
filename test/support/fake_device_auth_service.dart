import 'package:fav/features/settings/data/device_auth_service.dart';

/// Scriptable [DeviceAuthService] for tests.
class FakeDeviceAuthService implements DeviceAuthService {
  /// Creates the fake with scripted answers.
  FakeDeviceAuthService({
    this.available = true,
    this.outcome = DeviceAuthOutcome.passed,
  });

  /// Answer for [isAvailable].
  bool available;

  /// Answer for [authenticate].
  DeviceAuthOutcome outcome;

  /// When set, [authenticate] waits for it before answering — lets a test
  /// hold the system prompt open across lifecycle events.
  Future<void>? hold;

  /// When set, [authenticate] throws it — simulates an [Error] escaping the
  /// real service (which only maps [Exception]s).
  Error? thrown;

  /// Number of [authenticate] calls observed.
  int authenticateCalls = 0;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<DeviceAuthOutcome> authenticate(String reason) async {
    authenticateCalls++;
    final pending = hold;
    if (pending != null) await pending;
    final error = thrown;
    if (error != null) throw error;
    return outcome;
  }
}
