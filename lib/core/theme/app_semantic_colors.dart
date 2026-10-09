import 'package:fav/core/theme/app_colors.dart';
import 'package:flutter/material.dart';

/// Semantic colours that Material's [ColorScheme] does not provide.
///
/// [ColorScheme] covers `primary`/`surface`/`error`, but the mockups also use
/// success, warning, informational and code-block colours. Those are exposed
/// here as a [ThemeExtension] so they resolve from `Theme.of(context)` and
/// switch automatically with the active brightness.
@immutable
class AppSemanticColors extends ThemeExtension<AppSemanticColors> {
  /// Creates a set of semantic colours.
  const AppSemanticColors({
    required this.success,
    required this.successSurface,
    required this.warning,
    required this.warningSurface,
    required this.warningBorder,
    required this.info,
    required this.infoSurface,
    required this.codeBackground,
  });

  /// Semantic colours for the light theme.
  static const AppSemanticColors light = AppSemanticColors(
    success: AppColors.lightSuccess,
    successSurface: AppColors.lightSuccessSurface,
    warning: AppColors.lightWarning,
    warningSurface: AppColors.lightWarningSurface,
    warningBorder: AppColors.lightWarningBorder,
    info: AppColors.lightInfo,
    infoSurface: AppColors.lightInfoSurface,
    codeBackground: AppColors.lightCodeBackground,
  );

  /// Semantic colours for the dark theme.
  static const AppSemanticColors dark = AppSemanticColors(
    success: AppColors.darkSuccess,
    successSurface: AppColors.darkSuccessSurface,
    warning: AppColors.darkWarning,
    warningSurface: AppColors.darkWarningSurface,
    warningBorder: AppColors.darkWarningBorder,
    info: AppColors.darkInfo,
    infoSurface: AppColors.darkInfoSurface,
    codeBackground: AppColors.darkCodeBackground,
  );

  /// Foreground colour for success states (icons, text, badges).
  final Color success;

  /// Surface colour for success badges and banners.
  final Color successSurface;

  /// Foreground colour for warning states.
  final Color warning;

  /// Surface colour for warning badges and banners.
  final Color warningSurface;

  /// Border colour for warning banners.
  final Color warningBorder;

  /// Foreground colour for informational states.
  final Color info;

  /// Surface colour for informational badges and banners.
  final Color infoSurface;

  /// Background colour for monospace code blocks.
  final Color codeBackground;

  @override
  AppSemanticColors copyWith({
    Color? success,
    Color? successSurface,
    Color? warning,
    Color? warningSurface,
    Color? warningBorder,
    Color? info,
    Color? infoSurface,
    Color? codeBackground,
  }) {
    return AppSemanticColors(
      success: success ?? this.success,
      successSurface: successSurface ?? this.successSurface,
      warning: warning ?? this.warning,
      warningSurface: warningSurface ?? this.warningSurface,
      warningBorder: warningBorder ?? this.warningBorder,
      info: info ?? this.info,
      infoSurface: infoSurface ?? this.infoSurface,
      codeBackground: codeBackground ?? this.codeBackground,
    );
  }

  @override
  AppSemanticColors lerp(ThemeExtension<AppSemanticColors>? other, double t) {
    if (other is! AppSemanticColors) {
      return this;
    }
    return AppSemanticColors(
      success: Color.lerp(success, other.success, t)!,
      successSurface: Color.lerp(successSurface, other.successSurface, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      warningSurface: Color.lerp(warningSurface, other.warningSurface, t)!,
      warningBorder: Color.lerp(warningBorder, other.warningBorder, t)!,
      info: Color.lerp(info, other.info, t)!,
      infoSurface: Color.lerp(infoSurface, other.infoSurface, t)!,
      codeBackground: Color.lerp(codeBackground, other.codeBackground, t)!,
    );
  }
}

/// Convenient access to [AppSemanticColors] from a [BuildContext].
extension AppSemanticColorsX on BuildContext {
  /// The [AppSemanticColors] of the nearest enclosing [Theme].
  AppSemanticColors get semantic =>
      Theme.of(this).extension<AppSemanticColors>()!;
}
