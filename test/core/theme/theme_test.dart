import 'package:fav/core/theme/app_colors.dart';
import 'package:fav/core/theme/app_semantic_colors.dart';
import 'package:fav/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Unit tests for the assembled light/dark themes.
void main() {
  test('lightTheme uses the light brightness and the Primer accent', () {
    expect(lightTheme.brightness, Brightness.light);
    expect(lightTheme.colorScheme.primary, AppColors.lightAccent);
    expect(lightTheme.scaffoldBackgroundColor, AppColors.lightCanvas);
  });

  test('darkTheme uses the dark brightness and the Primer accent', () {
    expect(darkTheme.brightness, Brightness.dark);
    expect(darkTheme.colorScheme.primary, AppColors.darkAccent);
    expect(darkTheme.scaffoldBackgroundColor, AppColors.darkCanvas);
  });

  test('both themes carry the AppSemanticColors extension', () {
    expect(
      lightTheme.extension<AppSemanticColors>(),
      same(AppSemanticColors.light),
    );
    expect(
      darkTheme.extension<AppSemanticColors>(),
      same(AppSemanticColors.dark),
    );
  });

  test('form-field errors may wrap instead of truncating to one line', () {
    // The longest localized short error message is ~200 chars (F10): a
    // one-line default ellipsises the actionable tail on a phone.
    expect(lightTheme.inputDecorationTheme.errorMaxLines, 5);
    expect(darkTheme.inputDecorationTheme.errorMaxLines, 5);
  });

  test('the AppBar theme is flat and surface-coloured', () {
    expect(lightTheme.appBarTheme.elevation, 0);
    expect(lightTheme.appBarTheme.centerTitle, false);
    expect(lightTheme.appBarTheme.backgroundColor, AppColors.lightSurface);
  });

  test('snackbars expose close and horizontal swipe dismissal', () {
    for (final theme in [lightTheme, darkTheme]) {
      expect(theme.snackBarTheme.showCloseIcon, isTrue);
      expect(theme.snackBarTheme.dismissDirection, DismissDirection.horizontal);
      expect(
        theme.snackBarTheme.closeIconColor,
        theme.colorScheme.onInverseSurface,
      );
    }
  });
}
