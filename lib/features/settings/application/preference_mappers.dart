import 'package:fav/features/settings/domain/app_theme_mode.dart';
import 'package:fav/features/settings/domain/locale_choice.dart';
import 'package:flutter/material.dart' show Locale, ThemeMode;

/// Maps the Flutter-free [AppThemeMode] domain enum to Flutter's [ThemeMode].
extension AppThemeModeMaterial on AppThemeMode {
  /// Returns the matching `MaterialApp.themeMode` value.
  ThemeMode toMaterial() {
    return switch (this) {
      AppThemeMode.system => ThemeMode.system,
      AppThemeMode.light => ThemeMode.light,
      AppThemeMode.dark => ThemeMode.dark,
    };
  }
}

/// Maps a [LocaleChoice] to a Flutter [Locale] for `MaterialApp.locale`.
extension LocaleChoiceMaterial on LocaleChoice {
  /// Returns the forced [Locale], or `null` to let `flutter_localizations`
  /// resolve against the platform.
  Locale? toLocale() {
    final code = this.code;
    return code == null ? null : Locale(code);
  }
}
