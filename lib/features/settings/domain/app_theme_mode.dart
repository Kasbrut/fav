/// Theme preference persisted in user preferences.
///
/// A Flutter-free domain mirror of `ThemeMode`; the presentation layer maps it
/// to `ThemeMode` for `MaterialApp.themeMode` (see `preference_mappers.dart`).
/// The enum names match `ThemeMode`'s, so persisted records stay compatible.
enum AppThemeMode {
  /// Follow the OS light/dark setting.
  system,

  /// Force the light theme.
  light,

  /// Force the dark theme.
  dark;

  /// Parses [name] safely. Unknown values map to [AppThemeMode.system].
  static AppThemeMode parse(String? name) {
    for (final value in AppThemeMode.values) {
      if (value.name == name) return value;
    }
    return AppThemeMode.system;
  }
}
