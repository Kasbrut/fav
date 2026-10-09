import 'package:fav/core/theme/app_dimens.dart';
import 'package:flutter/material.dart';

/// Rounded shape shared by buttons, inputs and banners.
final RoundedRectangleBorder _controlShape = RoundedRectangleBorder(
  borderRadius: BorderRadius.circular(AppRadii.control),
);

/// Rounded shape shared by cards and dialogs.
final RoundedRectangleBorder _cardShape = RoundedRectangleBorder(
  borderRadius: BorderRadius.circular(AppRadii.card),
);

/// Builds the [AppBarTheme] — flat, surface-coloured, left-aligned title.
AppBarTheme buildAppBarTheme(ColorScheme scheme) {
  return AppBarTheme(
    centerTitle: false,
    elevation: 0,
    scrolledUnderElevation: 0,
    backgroundColor: scheme.surface,
    foregroundColor: scheme.onSurface,
    surfaceTintColor: Colors.transparent,
  );
}

/// Builds the [CardThemeData] — flat surface with a hairline border.
CardThemeData buildCardTheme(ColorScheme scheme) {
  return CardThemeData(
    elevation: 0,
    margin: EdgeInsets.zero,
    color: scheme.surface,
    surfaceTintColor: Colors.transparent,
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadii.card),
      side: BorderSide(color: scheme.outlineVariant),
    ),
  );
}

/// Builds the [FloatingActionButtonThemeData] — a flat, accent FAB that obeys
/// the No-Shadow Rule and shares the 8px control radius of the primary button.
FloatingActionButtonThemeData buildFloatingActionButtonTheme(
  ColorScheme scheme,
) {
  return FloatingActionButtonThemeData(
    elevation: 0,
    focusElevation: 0,
    hoverElevation: 0,
    highlightElevation: 0,
    disabledElevation: 0,
    backgroundColor: scheme.primary,
    foregroundColor: scheme.onPrimary,
    shape: _controlShape,
  );
}

/// Builds the [InputDecorationTheme] — filled fields with rounded borders.
InputDecorationTheme buildInputDecorationTheme(ColorScheme scheme) {
  OutlineInputBorder border(Color color, [double width = 1]) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadii.control),
      borderSide: BorderSide(color: color, width: width),
    );
  }

  return InputDecorationTheme(
    filled: true,
    fillColor: scheme.surface,
    isDense: true,
    // Localized error messages run up to ~200 chars; the one-line default
    // ellipsises the actionable tail on a phone (audit F10).
    errorMaxLines: 5,
    contentPadding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.md,
      vertical: AppSpacing.md,
    ),
    border: border(scheme.outline),
    enabledBorder: border(scheme.outline),
    focusedBorder: border(scheme.primary, 1.5),
    errorBorder: border(scheme.error),
    focusedErrorBorder: border(scheme.error, 1.5),
  );
}

/// Builds the [FilledButtonThemeData] — full-height primary action button.
FilledButtonThemeData buildFilledButtonTheme() {
  return FilledButtonThemeData(
    style: FilledButton.styleFrom(
      minimumSize: const Size(0, AppSizes.minTouchTarget),
      shape: _controlShape,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
    ),
  );
}

/// Builds the [OutlinedButtonThemeData] — full-height secondary action button.
OutlinedButtonThemeData buildOutlinedButtonTheme(ColorScheme scheme) {
  return OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      minimumSize: const Size(0, AppSizes.minTouchTarget),
      shape: _controlShape,
      side: BorderSide(color: scheme.outline),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
    ),
  );
}

/// Builds the [TextButtonThemeData] — used for low-emphasis actions.
TextButtonThemeData buildTextButtonTheme() {
  return TextButtonThemeData(
    style: TextButton.styleFrom(
      minimumSize: const Size(0, AppSizes.minTouchTarget),
      shape: _controlShape,
    ),
  );
}

/// Builds the [NavigationBarThemeData] for the bottom navigation bar.
NavigationBarThemeData buildNavigationBarTheme(ColorScheme scheme) {
  return NavigationBarThemeData(
    backgroundColor: scheme.surface,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    height: 64,
    indicatorColor: scheme.primary.withValues(alpha: 0.12),
    labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
  );
}

/// Builds the wide-layout navigation rail from the same visual tokens.
NavigationRailThemeData buildNavigationRailTheme(ColorScheme scheme) {
  return NavigationRailThemeData(
    backgroundColor: scheme.surface,
    indicatorColor: scheme.primary.withValues(alpha: 0.12),
    indicatorShape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadii.control),
    ),
    selectedIconTheme: IconThemeData(color: scheme.primary),
    unselectedIconTheme: IconThemeData(color: scheme.onSurfaceVariant),
    selectedLabelTextStyle: TextStyle(
      color: scheme.primary,
      fontWeight: FontWeight.w600,
    ),
    unselectedLabelTextStyle: TextStyle(color: scheme.onSurfaceVariant),
  );
}

/// Builds a quiet desktop scrollbar that remains visible during interaction.
ScrollbarThemeData buildScrollbarTheme(ColorScheme scheme) {
  return ScrollbarThemeData(
    thickness: const WidgetStatePropertyAll(6),
    radius: const Radius.circular(AppRadii.badge),
    thumbColor: WidgetStateProperty.resolveWith((states) {
      final opacity = states.contains(WidgetState.hovered) ? 0.65 : 0.4;
      return scheme.onSurfaceVariant.withValues(alpha: opacity);
    }),
  );
}

/// Builds the [SwitchThemeData].
///
/// Material 3's default off-state thumb resolves to `outline`, which on this
/// dark palette is almost the same tone as the off-state track, leaving the
/// thumb invisible. Pin the thumb to a contrasting tone in every state so the
/// off position always reads as a switch.
SwitchThemeData buildSwitchTheme(ColorScheme scheme) {
  return SwitchThemeData(
    thumbColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) {
        return scheme.onSurface.withValues(alpha: 0.38);
      }
      if (states.contains(WidgetState.selected)) {
        return scheme.onPrimary;
      }
      return scheme.onSurfaceVariant;
    }),
    trackColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) {
        return scheme.surfaceContainerHighest.withValues(alpha: 0.5);
      }
      if (states.contains(WidgetState.selected)) {
        return scheme.primary;
      }
      return scheme.surfaceContainerHighest;
    }),
    trackOutlineColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.selected)) {
        return Colors.transparent;
      }
      return scheme.outline;
    }),
  );
}

/// Builds the [DialogThemeData] — rounded surface matching cards.
DialogThemeData buildDialogTheme(ColorScheme scheme) {
  return DialogThemeData(
    backgroundColor: scheme.surface,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    shape: _cardShape,
  );
}

/// Builds the [DividerThemeData] — a 1 px hairline in the subtle border tone.
DividerThemeData buildDividerTheme(ColorScheme scheme) {
  return DividerThemeData(
    color: scheme.outlineVariant,
    space: 1,
    thickness: 1,
  );
}

/// Builds the [SnackBarThemeData].
SnackBarThemeData buildSnackBarTheme(ColorScheme scheme) {
  return SnackBarThemeData(
    behavior: SnackBarBehavior.floating,
    backgroundColor: scheme.inverseSurface,
    contentTextStyle: TextStyle(color: scheme.onInverseSurface),
    showCloseIcon: true,
    closeIconColor: scheme.onInverseSurface,
    dismissDirection: DismissDirection.horizontal,
    shape: _controlShape,
  );
}
