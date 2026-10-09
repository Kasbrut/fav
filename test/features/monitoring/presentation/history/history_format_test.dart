import 'package:fav/features/monitoring/presentation/history/history_format.dart';
import 'package:fav/l10n/app_localizations.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatBytes', () {
    test('renders < 1KB as plain bytes', () {
      expect(formatBytes(0), '0B');
      expect(formatBytes(512), '512B');
    });

    test('switches to KB/MB/GB at the right thresholds', () {
      expect(formatBytes(1024), '1KB');
      expect(formatBytes(1536), '1.5KB');
      expect(formatBytes(1024 * 1024), '1MB');
      expect(formatBytes(1024 * 1024 * 1024), '1GB');
    });
  });

  group('formatDuration', () {
    late AppLocalizations l10n;

    setUpAll(() async {
      await loadAppLocalizations();
      l10n = await AppLocalizations.delegate.load(const Locale('en'));
    });

    test('uses h+m for durations >= 1 hour', () {
      expect(
        formatDuration(l10n, const Duration(hours: 1, minutes: 5)),
        '1h 5m',
      );
      expect(formatDuration(l10n, const Duration(hours: 25)), '25h 0m');
    });

    test('uses m+s for durations < 1 hour', () {
      expect(formatDuration(l10n, const Duration(minutes: 5)), '5m 0s');
      expect(
        formatDuration(l10n, const Duration(seconds: 45)),
        '0m 45s',
      );
    });
  });
}

Future<void> loadAppLocalizations() async {
  TestWidgetsFlutterBinding.ensureInitialized();
}
