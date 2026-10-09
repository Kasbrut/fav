import 'package:flutter/material.dart';

/// Primary monospace font family for code and configuration text.
///
/// No font asset is bundled — the platform monospace face is used. The
/// mockups themselves specify `'SF Mono', Menlo, monospace`, i.e. system
/// fonts; [kMonospaceFontFallback] covers platforms without 'SF Mono'.
const String kMonospacePrimaryFont = 'SF Mono';

/// Fallback monospace font families, tried in order after
/// [kMonospacePrimaryFont].
const List<String> kMonospaceFontFallback = <String>[
  'Menlo',
  'Consolas',
  'Roboto Mono',
  'monospace',
];

/// Builds the shared [TextTheme] from the mockup type scale.
///
/// Text colours are left null so [ThemeData] resolves them from the active
/// [ColorScheme]; the font family is left null so the platform sans-serif is
/// used (the mockups specify the system UI font).
TextTheme buildTextTheme() {
  return const TextTheme(
    headlineSmall: TextStyle(
      fontSize: 22,
      fontWeight: FontWeight.w700,
      height: 1.3,
    ),
    titleLarge: TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.w700,
      height: 1.3,
    ),
    titleMedium: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w600,
      height: 1.3,
    ),
    titleSmall: TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      height: 1.3,
    ),
    bodyLarge: TextStyle(
      fontSize: 15,
      height: 1.45,
    ),
    bodyMedium: TextStyle(
      fontSize: 14,
      height: 1.45,
    ),
    bodySmall: TextStyle(
      fontSize: 12,
      height: 1.4,
    ),
    labelLarge: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      height: 1.2,
    ),
    labelMedium: TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      height: 1.2,
    ),
    labelSmall: TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      height: 1.2,
      letterSpacing: 0.4,
    ),
  );
}
