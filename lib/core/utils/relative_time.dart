import 'package:fav/l10n/app_localizations.dart';

/// Formats [time] as a short localized relative string.
///
/// Examples: "Just now", "12m ago", "3h ago", "2d ago". A `null` [time]
/// yields the "never connected" label. [now] is injectable for tests.
String relativeTime(AppLocalizations l10n, DateTime? time, {DateTime? now}) {
  if (time == null) {
    return l10n.lastSeenNever;
  }
  final difference = (now ?? DateTime.now()).difference(time);
  if (difference.inMinutes < 1) {
    return l10n.lastSeenJustNow;
  }
  if (difference.inHours < 1) {
    return l10n.lastSeenMinutesAgo(difference.inMinutes);
  }
  if (difference.inDays < 1) {
    return l10n.lastSeenHoursAgo(difference.inHours);
  }
  return l10n.lastSeenDaysAgo(difference.inDays);
}
