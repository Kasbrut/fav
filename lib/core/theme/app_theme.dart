import 'package:fav/core/theme/app_color_scheme.dart';
import 'package:fav/core/theme/app_colors.dart';
import 'package:fav/core/theme/app_component_themes.dart';
import 'package:fav/core/theme/app_semantic_colors.dart';
import 'package:fav/core/theme/app_text_theme.dart';
import 'package:flutter/material.dart';

/// Assembles a [ThemeData] from the design-system tokens.
ThemeData _buildTheme({
  required ColorScheme scheme,
  required Color canvas,
  required AppSemanticColors semantic,
}) {
  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: canvas,
    textTheme: buildTextTheme().apply(
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
    ),
    appBarTheme: buildAppBarTheme(scheme),
    cardTheme: buildCardTheme(scheme),
    inputDecorationTheme: buildInputDecorationTheme(scheme),
    filledButtonTheme: buildFilledButtonTheme(),
    floatingActionButtonTheme: buildFloatingActionButtonTheme(scheme),
    outlinedButtonTheme: buildOutlinedButtonTheme(scheme),
    textButtonTheme: buildTextButtonTheme(),
    navigationBarTheme: buildNavigationBarTheme(scheme),
    navigationRailTheme: buildNavigationRailTheme(scheme),
    scrollbarTheme: buildScrollbarTheme(scheme),
    switchTheme: buildSwitchTheme(scheme),
    dialogTheme: buildDialogTheme(scheme),
    dividerTheme: buildDividerTheme(scheme),
    snackBarTheme: buildSnackBarTheme(scheme),
    extensions: <ThemeExtension<dynamic>>[semantic],
  );
}

/// Material 3 theme used when the system is in light mode.
final ThemeData lightTheme = _buildTheme(
  scheme: buildLightColorScheme(),
  canvas: AppColors.lightCanvas,
  semantic: AppSemanticColors.light,
);

/// Material 3 theme used when the system is in dark mode.
final ThemeData darkTheme = _buildTheme(
  scheme: buildDarkColorScheme(),
  canvas: AppColors.darkCanvas,
  semantic: AppSemanticColors.dark,
);
