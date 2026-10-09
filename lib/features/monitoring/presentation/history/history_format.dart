import 'package:fav/core/theme/app_text_theme.dart';
import 'package:fav/l10n/app_localizations.dart';

/// The design-system monospace family for a pubkey fallback label, or `null`
/// for proportional text. Pairs with [monoFallbackFor] in a text style.
String? monoFamilyFor({required bool isFallback}) =>
    isFallback ? kMonospacePrimaryFont : null;

/// The monospace fallback stack matching [monoFamilyFor].
List<String>? monoFallbackFor({required bool isFallback}) =>
    isFallback ? kMonospaceFontFallback : null;

/// Formats a byte count using binary-ish units (KB / MB / GB) with one
/// fractional digit. Localization-independent — units are abbreviations.
String formatBytes(int bytes) {
  if (bytes < 1024) {
    return '${bytes}B';
  }
  const labels = ['KB', 'MB', 'GB', 'TB'];
  var value = bytes / 1024;
  var label = labels.first;
  for (final candidate in labels.skip(1)) {
    if (value < 1024) {
      break;
    }
    value /= 1024;
    label = candidate;
  }
  // Round to 1 decimal place; trim ".0" to keep "1KB" not "1.0KB".
  final rounded = (value * 10).round() / 10;
  final text = rounded == rounded.truncate()
      ? rounded.truncate().toString()
      : rounded.toStringAsFixed(1);
  return '$text$label';
}

/// Formats a duration as "{h}h {m}m" when ≥ 1h, "{m}m {s}s" otherwise.
String formatDuration(AppLocalizations l10n, Duration duration) {
  if (duration.inHours >= 1) {
    return l10n.historyDurationHm(
      duration.inHours,
      duration.inMinutes.remainder(60),
    );
  }
  return l10n.historyDurationMs(
    duration.inMinutes,
    duration.inSeconds.remainder(60),
  );
}
