import 'package:fav/features/settings/data/preferences_repository.dart';
import 'package:fav/features/settings/domain/app_lock_timeout.dart';
import 'package:fav/features/settings/domain/app_theme_mode.dart';
import 'package:fav/features/settings/domain/locale_choice.dart';
import 'package:fav/features/settings/domain/timestamped_error.dart';
import 'package:fav/features/settings/domain/user_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Overridden at `main()` boot with a repository over the opened
/// `preferences` Hive box.
final Provider<PreferencesRepository> preferencesRepositoryProvider =
    Provider<PreferencesRepository>(
      (ref) => throw UnimplementedError(
        'preferencesRepositoryProvider must be overridden',
      ),
    );

/// Single source of truth for [UserPreferences]. Synchronous hydration is
/// possible because the underlying box is already open before runApp.
class PreferencesController extends Notifier<UserPreferences> {
  /// Serializes mutations: each update reads the current [state] and writes
  /// only after every earlier mutation has settled, so two overlapping updates
  /// (e.g. a user's setLocale racing an automatic recordError) never clobber
  /// each other with a stale snapshot (audit H7).
  Future<void> _lock = Future<void>.value();

  @override
  UserPreferences build() {
    return ref.read(preferencesRepositoryProvider).readSync();
  }

  /// Runs [update] against the freshest state under the mutation lock. When it
  /// returns the current state unchanged, the write is skipped.
  Future<void> _mutate(UserPreferences Function(UserPreferences) update) {
    final result = _lock.then((_) async {
      final next = update(state);
      if (next == state) {
        return;
      }
      await ref.read(preferencesRepositoryProvider).write(next);
      state = next;
    });
    // Keep the chain alive even if one mutation throws.
    _lock = result.then((_) {}, onError: (_) {});
    return result;
  }

  /// Persists a new theme choice and updates state.
  Future<void> setThemeMode(AppThemeMode mode) =>
      _mutate((s) => s.copyWith(themeMode: mode));

  /// Persists a new locale choice and updates state.
  Future<void> setLocale(LocaleChoice choice) =>
      _mutate((s) => s.copyWith(localeChoice: choice));

  /// Persists the app-lock switch and updates state.
  Future<void> setAppLockEnabled({required bool enabled}) =>
      _mutate((s) => s.copyWith(appLockEnabled: enabled));

  /// Persists the desktop focus-loss grace period.
  Future<void> setAppLockTimeout(AppLockTimeout timeout) =>
      _mutate((s) => s.copyWith(appLockTimeout: timeout));

  /// Records [codeId] into the recent-errors ring buffer. Capped at 20,
  /// most recent first, consecutive duplicates of the same code skipped.
  Future<void> recordError(String codeId, DateTime when) {
    return _mutate((s) {
      if (s.recentErrors.isNotEmpty && s.recentErrors.first.codeId == codeId) {
        return s;
      }
      const cap = 20;
      final entry = TimestampedError(timestamp: when.toUtc(), codeId: codeId);
      final next = [entry, ...s.recentErrors];
      final trimmed = next.length > cap ? next.sublist(0, cap) : next;
      return s.copyWith(recentErrors: trimmed);
    });
  }
}

/// Provides the [PreferencesController].
final NotifierProvider<PreferencesController, UserPreferences>
preferencesControllerProvider =
    NotifierProvider<PreferencesController, UserPreferences>(
      PreferencesController.new,
    );
