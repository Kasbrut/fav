/// Spacing scale (logical pixels) used across the app, taken from the mockups.
///
/// Spacing is brightness-invariant, so it is exposed as plain constants
/// rather than through a `ThemeExtension`.
abstract final class AppSpacing {
  /// Extra-small spacing — 4 px.
  static const double xs = 4;

  /// Small spacing — 8 px.
  static const double sm = 8;

  /// Medium spacing — 12 px.
  static const double md = 12;

  /// Large spacing — 16 px.
  static const double lg = 16;

  /// Extra-large spacing — 24 px.
  static const double xl = 24;

  /// Double-extra-large spacing — 40 px.
  ///
  /// Mainly used as the bottom inset of scrollable screen bodies so the last
  /// control isn't flush against the bottom edge.
  static const double xxl = 40;
}

/// Corner radii (logical pixels) used across the app, taken from the mockups.
abstract final class AppRadii {
  /// Radius for small pills and badges — 6 px.
  static const double badge = 6;

  /// Radius for banners, buttons and input fields — 8 px.
  static const double control = 8;

  /// Radius for cards and dialogs — 12 px.
  static const double card = 12;

  /// Radius for large containers, such as the QR frame — 16 px.
  static const double large = 16;
}

/// Fixed sizes (logical pixels) used across the app.
abstract final class AppSizes {
  /// Shared maximum width for full-page content on tablets and desktops.
  static const double contentMaxWidth = 900;

  /// Maximum width for focused confirmation dialogs on large displays.
  static const double dialogMaxWidth = 560;

  /// Minimum interactive target size for accessibility — 48 px.
  static const double minTouchTarget = 48;

  /// Size of status icons shown in list tiles — 20 px.
  static const double statusIcon = 20;

  /// Size of the illustration icon shown in empty states — 64 px.
  static const double emptyStateIcon = 64;
}
