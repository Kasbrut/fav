import 'package:fav/features/settings/application/locale_override_provider.dart';
import 'package:fav/features/settings/application/preferences_controller.dart';
import 'package:fav/features/settings/application/theme_mode_provider.dart';
import 'package:fav/features/settings/data/preferences_repository.dart';
import 'package:fav/features/settings/domain/app_theme_mode.dart';
import 'package:fav/features/settings/domain/locale_choice.dart';
import 'package:fav/features/settings/domain/user_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeRepo implements PreferencesRepository {
  _FakeRepo([UserPreferences? initial])
    : _current = initial ?? UserPreferences.defaults;

  UserPreferences _current;
  int writeCount = 0;

  @override
  UserPreferences readSync() => _current;

  @override
  Future<void> write(UserPreferences prefs) async {
    writeCount++;
    _current = prefs;
  }
}

void main() {
  test('preferencesController hydrates from the repository', () {
    final repo = _FakeRepo(
      UserPreferences.defaults.copyWith(themeMode: AppThemeMode.dark),
    );
    final container = ProviderContainer(
      overrides: [
        preferencesRepositoryProvider.overrideWithValue(repo),
      ],
    );
    addTearDown(container.dispose);
    expect(
      container.read(preferencesControllerProvider).themeMode,
      AppThemeMode.dark,
    );
  });

  test('setThemeMode updates state and persists', () async {
    final repo = _FakeRepo();
    final container = ProviderContainer(
      overrides: [
        preferencesRepositoryProvider.overrideWithValue(repo),
      ],
    );
    addTearDown(container.dispose);
    await container
        .read(preferencesControllerProvider.notifier)
        .setThemeMode(AppThemeMode.light);
    expect(container.read(themeModeProvider), AppThemeMode.light);
    expect(repo.writeCount, 1);
  });

  test('setLocale changes the override', () async {
    final repo = _FakeRepo();
    final container = ProviderContainer(
      overrides: [
        preferencesRepositoryProvider.overrideWithValue(repo),
      ],
    );
    addTearDown(container.dispose);
    await container
        .read(preferencesControllerProvider.notifier)
        .setLocale(LocaleChoice.forCode('it'));
    expect(
      container.read(localeOverrideProvider),
      const Locale('it'),
    );
  });

  test('concurrent theme + locale updates both persist (H7)', () async {
    // Each mutator read `state` before its await, so two overlapping updates
    // clobbered each other — the last write won with a stale snapshot and the
    // other field's change was lost. Both must survive.
    final repo = _FakeRepo();
    final container = ProviderContainer(
      overrides: [preferencesRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    final notifier = container.read(preferencesControllerProvider.notifier);

    await Future.wait([
      notifier.setThemeMode(AppThemeMode.dark),
      notifier.setLocale(LocaleChoice.forCode('it')),
    ]);

    final prefs = container.read(preferencesControllerProvider);
    expect(prefs.themeMode, AppThemeMode.dark);
    expect(prefs.localeChoice.code, 'it');
    // Persisted state agrees with in-memory state.
    expect(repo.readSync().themeMode, AppThemeMode.dark);
    expect(repo.readSync().localeChoice.code, 'it');
  });

  test('setAppLockEnabled persists the flag', () async {
    final repo = _FakeRepo();
    final container = ProviderContainer(
      overrides: [
        preferencesRepositoryProvider.overrideWithValue(repo),
      ],
    );
    addTearDown(container.dispose);
    await container
        .read(preferencesControllerProvider.notifier)
        .setAppLockEnabled(enabled: true);
    expect(
      container.read(preferencesControllerProvider).appLockEnabled,
      isTrue,
    );
    expect(repo.readSync().appLockEnabled, isTrue);
  });

  test('setLocale system clears the override', () async {
    final repo = _FakeRepo(
      UserPreferences.defaults.copyWith(
        localeChoice: LocaleChoice.forCode('en'),
      ),
    );
    final container = ProviderContainer(
      overrides: [
        preferencesRepositoryProvider.overrideWithValue(repo),
      ],
    );
    addTearDown(container.dispose);
    await container
        .read(preferencesControllerProvider.notifier)
        .setLocale(LocaleChoice.system);
    expect(container.read(localeOverrideProvider), isNull);
  });
}
