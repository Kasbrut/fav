/// Delay before the app lock engages after the app loses focus.
enum AppLockTimeout {
  /// Lock after one minute.
  oneMinute('oneMinute', Duration(minutes: 1)),

  /// Lock after two minutes.
  twoMinutes('twoMinutes', Duration(minutes: 2)),

  /// Lock after five minutes.
  fiveMinutes('fiveMinutes', Duration(minutes: 5)),

  /// Lock only when a new app process starts.
  onlyOnLaunch('onlyOnLaunch', null);

  const AppLockTimeout(this.storageId, this.duration);

  /// Stable persisted identifier.
  final String storageId;

  /// Focus-loss grace period, or null when lifecycle locking is disabled.
  final Duration? duration;

  /// Parses persisted data, defaulting to one minute.
  static AppLockTimeout parse(String? value) {
    for (final option in values) {
      if (option.storageId == value) return option;
    }
    return oneMinute;
  }
}
