import 'package:fav/core/utils/relative_time.dart';
import 'package:fav/l10n/app_localizations.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tests for the [relativeTime] helper.
void main() {
  late AppLocalizations l10n;
  final now = DateTime(2026, 5, 18, 12);

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  test('a null time yields the never-connected label', () {
    expect(relativeTime(l10n, null, now: now), l10n.lastSeenNever);
  });

  test('under a minute yields the just-now label', () {
    final time = now.subtract(const Duration(seconds: 30));
    expect(relativeTime(l10n, time, now: now), l10n.lastSeenJustNow);
  });

  test('minutes, hours and days buckets', () {
    expect(
      relativeTime(l10n, now.subtract(const Duration(minutes: 10)), now: now),
      l10n.lastSeenMinutesAgo(10),
    );
    expect(
      relativeTime(l10n, now.subtract(const Duration(hours: 3)), now: now),
      l10n.lastSeenHoursAgo(3),
    );
    expect(
      relativeTime(l10n, now.subtract(const Duration(days: 2)), now: now),
      l10n.lastSeenDaysAgo(2),
    );
  });
}
