import 'package:fav/core/errors/app_exception.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// In-memory ring buffer of the last 3 [ErrorCode.id] values shown to the
/// user. Drives the "Recent error codes" line in the GitHub issue body
/// (`IssueUrlBuilder`). Not persisted — wiped on app restart by design
/// (the user is reporting *this* session).
class RecentErrorsNotifier extends Notifier<List<String>> {
  /// Capacity of the ring buffer.
  static const int maxEntries = 3;

  @override
  List<String> build() => const [];

  /// Records [code]. Skips if [code] is identical to the most recent entry.
  void record(ErrorCode code) {
    final id = code.id;
    if (state.isNotEmpty && state.first == id) return;
    final next = [id, ...state];
    state = next.length > maxEntries ? next.sublist(0, maxEntries) : next;
  }
}

/// Provides the recent-errors ring buffer.
final NotifierProvider<RecentErrorsNotifier, List<String>>
recentErrorsProvider = NotifierProvider<RecentErrorsNotifier, List<String>>(
  RecentErrorsNotifier.new,
);
