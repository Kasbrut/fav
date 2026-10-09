import 'package:fav/core/theme/app_colors.dart';
import 'package:flutter/material.dart';

/// Material [ColorScheme] for the light theme.
///
/// Built from a seed for completeness, then the roles that must match the
/// mockups exactly are overridden — the mockups are the authoritative design
/// reference, so the Primer palette is pinned rather than algorithmically
/// derived.
ColorScheme buildLightColorScheme() {
  return ColorScheme.fromSeed(
    seedColor: AppColors.lightAccent,
  ).copyWith(
    primary: AppColors.lightAccent,
    onPrimary: AppColors.onEmphasis,
    surface: AppColors.lightSurface,
    onSurface: AppColors.lightTextPrimary,
    onSurfaceVariant: AppColors.lightTextMuted,
    surfaceContainerLowest: AppColors.lightSurface,
    surfaceContainerLow: AppColors.lightCanvas,
    surfaceContainer: AppColors.lightSurfaceMuted,
    surfaceContainerHigh: AppColors.lightSurfaceMuted,
    surfaceContainerHighest: AppColors.lightNeutralSurface,
    outline: AppColors.lightBorder,
    outlineVariant: AppColors.lightBorderSubtle,
    error: AppColors.lightDanger,
    onError: AppColors.onEmphasis,
    errorContainer: AppColors.lightDangerSurface,
    onErrorContainer: AppColors.lightDanger,
  );
}

/// Material [ColorScheme] for the dark theme.
///
/// See [buildLightColorScheme] for the seed-then-override rationale.
ColorScheme buildDarkColorScheme() {
  return ColorScheme.fromSeed(
    seedColor: AppColors.darkAccent,
    brightness: Brightness.dark,
  ).copyWith(
    primary: AppColors.darkAccent,
    onPrimary: AppColors.onEmphasis,
    surface: AppColors.darkSurface,
    onSurface: AppColors.darkTextPrimary,
    onSurfaceVariant: AppColors.darkTextMuted,
    surfaceContainerLowest: AppColors.darkCanvas,
    surfaceContainerLow: AppColors.darkSurfaceMuted,
    surfaceContainer: AppColors.darkSurface,
    surfaceContainerHigh: AppColors.darkSurface,
    surfaceContainerHighest: AppColors.darkNeutralSurface,
    outline: AppColors.darkBorder,
    outlineVariant: AppColors.darkBorderSubtle,
    error: AppColors.darkDanger,
    onError: AppColors.onEmphasis,
    errorContainer: AppColors.darkDangerSurface,
    onErrorContainer: AppColors.darkDanger,
  );
}
