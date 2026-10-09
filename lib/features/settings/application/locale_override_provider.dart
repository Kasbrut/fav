import 'package:fav/features/settings/application/preference_mappers.dart';
import 'package:fav/features/settings/application/preferences_controller.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Read-only view of the active [Locale] override, or `null` when the user
/// chose "follow system". Use this from `MaterialApp.locale`.
final Provider<Locale?> localeOverrideProvider = Provider<Locale?>((ref) {
  return ref.watch(preferencesControllerProvider).localeChoice.toLocale();
});
