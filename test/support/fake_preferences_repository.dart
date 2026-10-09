import 'package:fav/features/settings/data/preferences_repository.dart';
import 'package:fav/features/settings/domain/user_preferences.dart';

/// In-memory [PreferencesRepository] for widget tests.
///
/// Starts with [UserPreferences.defaults] and ignores writes unless a test
/// needs to inspect them.
class FakePreferencesRepository implements PreferencesRepository {
  FakePreferencesRepository([UserPreferences? initial])
    : _current = initial ?? UserPreferences.defaults;

  UserPreferences _current;

  @override
  UserPreferences readSync() => _current;

  @override
  Future<void> write(UserPreferences prefs) async {
    _current = prefs;
  }
}
