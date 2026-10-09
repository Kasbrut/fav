import 'package:fav/features/settings/application/preferences_controller.dart';
import 'package:fav/features/settings/domain/timestamped_error.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Read-only view of the persisted recent-errors ring buffer (max 20,
/// most recent first). Backed by `UserPreferences.recentErrors`.
final Provider<List<TimestampedError>> errorHistoryProvider =
    Provider<List<TimestampedError>>((ref) {
      return ref.watch(preferencesControllerProvider).recentErrors;
    });
