import 'package:fav/features/settings/application/preferences_controller.dart';
import 'package:fav/features/settings/domain/app_theme_mode.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Read-only view of the active [AppThemeMode]. The root widget maps it to a
/// Flutter `ThemeMode` (via `preference_mappers.dart`) for
/// `MaterialApp.themeMode`.
final Provider<AppThemeMode> themeModeProvider = Provider<AppThemeMode>((ref) {
  return ref.watch(preferencesControllerProvider).themeMode;
});
