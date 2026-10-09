import 'package:fav/features/settings/domain/app_lock_timeout.dart';
import 'package:fav/features/settings/domain/app_theme_mode.dart';
import 'package:fav/features/settings/domain/locale_choice.dart';
import 'package:fav/features/settings/domain/timestamped_error.dart';
import 'package:meta/meta.dart';

/// Immutable snapshot of user-controlled preferences persisted in the
/// `preferences` Hive box.
@immutable
class UserPreferences {
  /// Creates a snapshot.
  const UserPreferences({
    required this.themeMode,
    required this.localeChoice,
    required this.schemaVersion,
    required this.recentErrors,
    required this.appLockEnabled,
    this.appLockTimeout = AppLockTimeout.oneMinute,
  });

  /// Parses a persisted map. Unknown enum values fall back to defaults.
  /// `schemaVersion` mismatches are accepted here; migration is the
  /// repository's responsibility.
  factory UserPreferences.fromJson(Map<dynamic, dynamic> json) {
    final mode = AppThemeMode.parse(json['themeMode'] as String?);
    final choice = LocaleChoice.parse(json['locale'] as String?);
    final rawErrors = json['recentErrors'];
    final errors = rawErrors is List
        ? rawErrors
              .whereType<Map<dynamic, dynamic>>()
              .map(TimestampedError.fromJson)
              .whereType<TimestampedError>()
              .toList()
        : <TimestampedError>[];
    final rawVersion = json['schemaVersion'];
    final schemaVersion = rawVersion is int ? rawVersion : currentSchemaVersion;
    final rawLock = json['appLockEnabled'];
    return UserPreferences(
      themeMode: mode,
      localeChoice: choice,
      schemaVersion: schemaVersion,
      recentErrors: errors,
      appLockEnabled: rawLock is bool && rawLock,
      appLockTimeout: AppLockTimeout.parse(json['appLockTimeout'] as String?),
    );
  }

  /// Current schema version of the persisted record.
  static const int currentSchemaVersion = 1;

  /// Default snapshot used when the box has no record yet.
  static const UserPreferences defaults = UserPreferences(
    themeMode: AppThemeMode.system,
    localeChoice: LocaleChoice.system,
    schemaVersion: currentSchemaVersion,
    recentErrors: [],
    appLockEnabled: false,
  );

  /// Selected theme preference (maps to `MaterialApp.themeMode`).
  final AppThemeMode themeMode;

  /// Active locale choice (drives `MaterialApp.locale`).
  final LocaleChoice localeChoice;

  /// Persisted record schema version.
  final int schemaVersion;

  /// Ring buffer of the most recent errors shown to the user (max 20,
  /// most recent first).
  final List<TimestampedError> recentErrors;

  /// Whether opening the app requires the device unlock (app lock).
  final bool appLockEnabled;

  /// Desktop grace period after the app loses focus.
  final AppLockTimeout appLockTimeout;

  /// Returns a copy with selected fields overridden.
  UserPreferences copyWith({
    AppThemeMode? themeMode,
    LocaleChoice? localeChoice,
    int? schemaVersion,
    List<TimestampedError>? recentErrors,
    bool? appLockEnabled,
    AppLockTimeout? appLockTimeout,
  }) {
    return UserPreferences(
      themeMode: themeMode ?? this.themeMode,
      localeChoice: localeChoice ?? this.localeChoice,
      schemaVersion: schemaVersion ?? this.schemaVersion,
      recentErrors: recentErrors ?? this.recentErrors,
      appLockEnabled: appLockEnabled ?? this.appLockEnabled,
      appLockTimeout: appLockTimeout ?? this.appLockTimeout,
    );
  }

  /// Encodes the snapshot as a JSON-shaped map for persistence.
  Map<String, dynamic> toJson() => {
    'themeMode': themeMode.name,
    'locale': localeChoice.storageId,
    'schemaVersion': schemaVersion,
    'recentErrors': recentErrors.map((e) => e.toJson()).toList(),
    'appLockEnabled': appLockEnabled,
    'appLockTimeout': appLockTimeout.storageId,
  };

  @override
  bool operator ==(Object other) {
    if (other is! UserPreferences) return false;
    if (other.themeMode != themeMode) return false;
    if (other.localeChoice != localeChoice) return false;
    if (other.schemaVersion != schemaVersion) return false;
    if (other.appLockEnabled != appLockEnabled) return false;
    if (other.appLockTimeout != appLockTimeout) return false;
    if (other.recentErrors.length != recentErrors.length) return false;
    for (var i = 0; i < recentErrors.length; i++) {
      if (recentErrors[i] != other.recentErrors[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    themeMode,
    localeChoice,
    schemaVersion,
    Object.hashAll(recentErrors),
    appLockEnabled,
    appLockTimeout,
  );
}
