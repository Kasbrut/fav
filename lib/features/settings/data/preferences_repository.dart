import 'package:fav/features/settings/domain/user_preferences.dart';
import 'package:hive_ce/hive.dart';

const String _prefsKey = 'user_prefs';

/// Typed read/write access to the `preferences` Hive box. Synchronous reads
/// are safe because the box is already open at `main()` boot time.
class PreferencesRepository {
  /// Creates a repository over [_box].
  PreferencesRepository(this._box);

  final Box<Map<dynamic, dynamic>> _box;

  /// Returns the current snapshot or [UserPreferences.defaults] when the
  /// box has no record or the record fails to parse.
  UserPreferences readSync() {
    final stored = _box.get(_prefsKey);
    if (stored == null) return UserPreferences.defaults;
    try {
      return UserPreferences.fromJson(stored);
    } on Object {
      return UserPreferences.defaults;
    }
  }

  /// Persists [prefs] to the box.
  Future<void> write(UserPreferences prefs) async {
    await _box.put(_prefsKey, prefs.toJson());
  }
}
