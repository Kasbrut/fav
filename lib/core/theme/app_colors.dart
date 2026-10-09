import 'package:flutter/material.dart';

/// Raw colour palette extracted from the design mockups, in the GitHub Primer
/// style.
///
/// These constants are the single source of truth fed into the theme
/// builders. Widgets must never reference them directly — they read the
/// resolved tokens from `Theme.of(context)` and the `AppSemanticColors`
/// extension instead.
abstract final class AppColors {
  // --- Light theme --------------------------------------------------------

  /// Light: app background shown behind cards and sheets.
  static const Color lightCanvas = Color(0xFFFAFAFA);

  /// Light: raised surface colour for cards, sheets and dialogs.
  static const Color lightSurface = Color(0xFFFFFFFF);

  /// Light: alternate surface used for inset/filled areas.
  static const Color lightSurfaceMuted = Color(0xFFF1F3F5);

  /// Light: neutral surface used for plain badges and chips.
  static const Color lightNeutralSurface = Color(0xFFEFF1F3);

  /// Light: default hairline border colour.
  static const Color lightBorder = Color(0xFFDDE1E6);

  /// Light: subtler border used for dividers.
  static const Color lightBorderSubtle = Color(0xFFE8EAEE);

  /// Light: primary text colour.
  static const Color lightTextPrimary = Color(0xFF1F2328);

  /// Light: muted/secondary text colour.
  static const Color lightTextMuted = Color(0xFF656D76);

  /// Light: brand accent colour, taken from the app logo's violet.
  static const Color lightAccent = Color(0xFF5E4089);

  /// Light: stronger accent used for pressed/hover states.
  static const Color lightAccentStrong = Color(0xFF4A3170);

  /// Light: success foreground colour.
  static const Color lightSuccess = Color(0xFF1A7F37);

  /// Light: success surface colour for badges and banners.
  static const Color lightSuccessSurface = Color(0xFFDAFBE1);

  /// Light: danger/error foreground colour.
  static const Color lightDanger = Color(0xFFCF222E);

  /// Light: danger/error surface colour.
  static const Color lightDangerSurface = Color(0xFFFFEBE9);

  /// Light: warning foreground colour.
  static const Color lightWarning = Color(0xFF9A6700);

  /// Light: warning surface colour.
  static const Color lightWarningSurface = Color(0xFFFFF8C5);

  /// Light: warning border colour.
  static const Color lightWarningBorder = Color(0xFFD4A72C);

  /// Light: informational foreground colour.
  static const Color lightInfo = Color(0xFF0969DA);

  /// Light: informational surface colour.
  static const Color lightInfoSurface = Color(0xFFDDF4FF);

  /// Light: background of monospace code blocks.
  static const Color lightCodeBackground = Color(0xFFF6F8FA);

  // --- Dark theme ---------------------------------------------------------

  /// Dark: app background shown behind cards and sheets.
  static const Color darkCanvas = Color(0xFF0A0A0A);

  /// Dark: raised surface colour for cards, sheets and dialogs.
  static const Color darkSurface = Color(0xFF21262D);

  /// Dark: alternate surface used for inset/filled areas.
  static const Color darkSurfaceMuted = Color(0xFF1C2128);

  /// Dark: neutral surface used for plain badges and chips.
  static const Color darkNeutralSurface = Color(0xFF2D333B);

  /// Dark: default hairline border colour.
  static const Color darkBorder = Color(0xFF30363D);

  /// Dark: subtler border used for dividers.
  static const Color darkBorderSubtle = Color(0xFF272D36);

  /// Dark: primary text colour.
  static const Color darkTextPrimary = Color(0xFFE6EDF3);

  /// Dark: muted/secondary text colour.
  static const Color darkTextMuted = Color(0xFF8B949E);

  /// Dark: brand accent colour — the logo's violet, lightened so a filled
  /// button reads as elevated against the near-black dark canvas.
  static const Color darkAccent = Color(0xFF8B6BC9);

  /// Dark: stronger accent used for pressed/hover states.
  static const Color darkAccentStrong = Color(0xFFA084D6);

  /// Dark: success foreground colour.
  static const Color darkSuccess = Color(0xFF3FB950);

  /// Dark: success surface colour for badges and banners.
  static const Color darkSuccessSurface = Color(0xFF182F1E);

  /// Dark: danger/error foreground colour.
  static const Color darkDanger = Color(0xFFF85149);

  /// Dark: danger/error surface colour.
  static const Color darkDangerSurface = Color(0xFF3D1518);

  /// Dark: warning foreground colour.
  static const Color darkWarning = Color(0xFFD29922);

  /// Dark: warning surface colour.
  static const Color darkWarningSurface = Color(0xFF3D2E0C);

  /// Dark: warning border colour.
  static const Color darkWarningBorder = Color(0xFF9E6A03);

  /// Dark: informational foreground colour.
  static const Color darkInfo = Color(0xFF58A6FF);

  /// Dark: informational surface colour.
  static const Color darkInfoSurface = Color(0xFF0D2A4D);

  /// Dark: background of monospace code blocks.
  static const Color darkCodeBackground = Color(0xFF161B22);

  // --- Shared -------------------------------------------------------------

  /// Foreground colour used on top of filled accent/success/danger surfaces.
  static const Color onEmphasis = Color(0xFFFFFFFF);
}
