import 'package:fav/features/settings/domain/app_lock_timeout.dart';
import 'package:fav/features/settings/domain/app_theme_mode.dart';
import 'package:fav/features/settings/domain/locale_choice.dart';
import 'package:fav/features/settings/domain/timestamped_error.dart';
import 'package:fav/features/settings/domain/user_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UserPreferences', () {
    test('defaults match the constants', () {
      const p = UserPreferences.defaults;
      expect(p.themeMode, AppThemeMode.system);
      expect(p.localeChoice, LocaleChoice.system);
      expect(p.appLockTimeout, AppLockTimeout.oneMinute);
      expect(p.schemaVersion, 1);
      expect(p.recentErrors, isEmpty);
    });

    test('roundtrips through JSON', () {
      final original = UserPreferences(
        themeMode: AppThemeMode.dark,
        localeChoice: LocaleChoice.forCode('it'),
        schemaVersion: 1,
        recentErrors: [
          TimestampedError(
            timestamp: DateTime.utc(2026, 5, 29, 12),
            codeId: 'ERR-CONN-01',
          ),
        ],
        appLockEnabled: true,
        appLockTimeout: AppLockTimeout.fiveMinutes,
      );
      final json = original.toJson();
      final parsed = UserPreferences.fromJson(json);
      expect(parsed, equals(original));
    });

    test('app lock timeout defaults safely and round-trips', () {
      expect(
        UserPreferences.fromJson(const {}).appLockTimeout,
        AppLockTimeout.oneMinute,
      );
      expect(
        UserPreferences.fromJson(
          const {'appLockTimeout': 'onlyOnLaunch'},
        ).appLockTimeout,
        AppLockTimeout.onlyOnLaunch,
      );
      expect(
        UserPreferences.fromJson(
          const {'appLockTimeout': 'unknown'},
        ).appLockTimeout,
        AppLockTimeout.oneMinute,
      );
    });

    test('falls back when JSON has unknown enum values', () {
      final parsed = UserPreferences.fromJson(const {
        'themeMode': 'rainbow',
        'locale': 'klingon',
        'schemaVersion': 1,
        'recentErrors': <Map<String, dynamic>>[],
      });
      expect(parsed.themeMode, AppThemeMode.system);
      expect(parsed.localeChoice, LocaleChoice.system);
    });

    test('appLockEnabled defaults to false and parses a stored true', () {
      expect(UserPreferences.fromJson(const {}).appLockEnabled, isFalse);
      expect(
        UserPreferences.fromJson(const {'appLockEnabled': true}).appLockEnabled,
        isTrue,
      );
    });

    test('appLockEnabled round-trips through toJson and affects equality', () {
      final prefs = UserPreferences.defaults.copyWith(appLockEnabled: true);
      expect(UserPreferences.fromJson(prefs.toJson()).appLockEnabled, isTrue);
      expect(prefs, isNot(equals(UserPreferences.defaults)));
    });

    test('discards malformed recentErrors entries', () {
      final parsed = UserPreferences.fromJson(const {
        'themeMode': 'system',
        'locale': 'en',
        'schemaVersion': 1,
        'recentErrors': [
          {'ts': '2026-05-29T12:00:00Z', 'code': 'ERR-CONN-01'},
          {'ts': 'not a date', 'code': 'ERR-X'},
          {'ts': '2026-05-29T13:00:00Z'}, // missing code
          'totally invalid',
        ],
      });
      expect(parsed.recentErrors, hasLength(1));
      expect(parsed.recentErrors.single.codeId, 'ERR-CONN-01');
    });
  });
}
