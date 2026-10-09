import 'dart:io';

import 'package:fav/features/settings/data/preferences_repository.dart';
import 'package:fav/features/settings/domain/app_theme_mode.dart';
import 'package:fav/features/settings/domain/locale_choice.dart';
import 'package:fav/features/settings/domain/timestamped_error.dart';
import 'package:fav/features/settings/domain/user_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

Future<Box<Map<dynamic, dynamic>>> _openBox(String dir) async {
  Hive.init(dir);
  return Hive.openBox<Map<dynamic, dynamic>>(
    'prefs_${DateTime.now().microsecondsSinceEpoch}',
  );
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('prefs_test_');
  });

  tearDown(() async {
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('readSync returns defaults when the box is empty', () async {
    final box = await _openBox(tempDir.path);
    final repo = PreferencesRepository(box);
    expect(repo.readSync(), equals(UserPreferences.defaults));
  });

  test('write persists and readSync returns the same snapshot', () async {
    final box = await _openBox(tempDir.path);
    final repo = PreferencesRepository(box);
    final next = UserPreferences.defaults.copyWith(
      themeMode: AppThemeMode.dark,
      localeChoice: LocaleChoice.forCode('it'),
      recentErrors: [
        TimestampedError(
          timestamp: DateTime.utc(2026, 5, 29, 12),
          codeId: 'ERR-CONN-01',
        ),
      ],
    );
    await repo.write(next);
    expect(repo.readSync(), equals(next));
  });

  test('readSync recovers when the stored map is malformed', () async {
    final box = await _openBox(tempDir.path);
    await box.put('user_prefs', {'totally': 'broken'});
    final repo = PreferencesRepository(box);
    expect(repo.readSync(), equals(UserPreferences.defaults));
  });
}
