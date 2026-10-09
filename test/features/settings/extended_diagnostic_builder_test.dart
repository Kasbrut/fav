import 'package:fav/features/help/data/issue_url_builder.dart';
import 'package:fav/features/settings/data/extended_diagnostic_builder.dart';
import 'package:fav/features/settings/domain/timestamped_error.dart';
import 'package:fav/features/settings/domain/user_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const base = IssueDiagnostic(
    appVersion: '1.0.0+12',
    platform: 'ios',
    osVersion: '17.4',
    locale: 'en',
    recentErrorCodes: ['ERR-CONN-01'],
  );

  const prefs = UserPreferences.defaults;

  test('renders a header + base fields', () {
    final out = ExtendedDiagnosticBuilder.build(
      base: base,
      serverSummaries: const [],
      recentErrors: const [],
      recentRuns: const [],
      preferences: prefs,
      customScriptsPresent: false,
      now: DateTime.utc(2026, 5, 29, 12),
    );
    expect(out, contains('=== FAV'));
    expect(out, contains('App: 1.0.0+12'));
    expect(out, contains('Platform: ios 17.4'));
    expect(out, contains('Locale (UI): en'));
    expect(out, contains('Theme: system'));
    expect(out, contains('Preferences schemaVersion: 1'));
  });

  test('lists server summaries', () {
    final out = ExtendedDiagnosticBuilder.build(
      base: base,
      serverSummaries: const [
        ServerSummary(
          osFamily: 'ubuntu-22.04',
          sshPort: 22,
          installState: 'installed',
          peerCount: 3,
          hostKeyPrefix: 'ab12cd34',
        ),
        ServerSummary(
          osFamily: 'debian-12',
          sshPort: 2222,
          installState: 'incomplete',
          peerCount: 0,
          hostKeyPrefix: 'ef56gh78',
        ),
      ],
      recentErrors: const [],
      recentRuns: const [],
      preferences: prefs,
      customScriptsPresent: true,
      now: DateTime.utc(2026, 5, 29, 12),
    );
    expect(out, contains('--- Servers (2) ---'));
    expect(out, contains('[1] os=ubuntu-22.04 sshPort=22'));
    expect(out, contains('[2] os=debian-12 sshPort=2222'));
    expect(out, contains('Custom scripts present: true'));
  });

  test('renders n/a for a server without a stored host key prefix', () {
    // The provider always passes '' (the pin lives in secure storage, not
    // in Hive — spec §4.2); a bare `hostKeyPrefix=` in the report reads
    // like a bug (seen in a real device report, 2026-09-08).
    final out = ExtendedDiagnosticBuilder.build(
      base: base,
      serverSummaries: const [
        ServerSummary(
          osFamily: 'debian',
          sshPort: 22,
          installState: 'installed',
          peerCount: 1,
          hostKeyPrefix: '',
        ),
      ],
      recentErrors: const [],
      recentRuns: const [],
      preferences: prefs,
      customScriptsPresent: false,
      now: DateTime.utc(2026, 9, 8),
    );
    expect(out, contains('hostKeyPrefix=n/a'));
  });

  test('renders recent errors and recent runs with timestamps', () {
    final out = ExtendedDiagnosticBuilder.build(
      base: base,
      serverSummaries: const [],
      recentErrors: [
        TimestampedError(
          timestamp: DateTime.utc(2026, 5, 29, 11),
          codeId: 'ERR-CONN-01',
        ),
        TimestampedError(
          timestamp: DateTime.utc(2026, 5, 29, 10),
          codeId: 'ERR-AUTH-02',
        ),
      ],
      recentRuns: const [
        RunSummary(
          runId: 'a1b2c3',
          outcome: 'success',
          finalStep: 'zz_finalize',
          when: '2026-05-29T13:00:00Z',
        ),
        RunSummary(
          runId: 'd4e5f6',
          outcome: 'failed',
          finalStep: '40_write_server_conf',
          when: '2026-05-29T12:30:00Z',
        ),
      ],
      preferences: prefs,
      customScriptsPresent: false,
      now: DateTime.utc(2026, 5, 29, 12),
    );
    expect(out, contains('2026-05-29T11:00:00.000Z ERR-CONN-01'));
    expect(out, contains('run=a1b2c3 outcome=success'));
    expect(out, contains('run=d4e5f6 outcome=failed'));
  });

  test('sanitization: poisoned data never leaks', () {
    final out = ExtendedDiagnosticBuilder.build(
      base: const IssueDiagnostic(
        appVersion: '1.0.0+12',
        platform: 'ios',
        osVersion: '17.4',
        locale: 'en',
        recentErrorCodes: [],
      ),
      serverSummaries: const [
        ServerSummary(
          osFamily: 'ubuntu-22.04',
          sshPort: 22,
          installState: 'installed',
          peerCount: 3,
          hostKeyPrefix: 'ab12cd34',
        ),
      ],
      recentErrors: const [],
      recentRuns: const [],
      preferences: prefs,
      customScriptsPresent: false,
      now: DateTime.utc(2026, 5, 29, 12),
    );
    // Tokens that should never appear in any bundle.
    expect(out, isNot(contains('192.168')));
    expect(out, isNot(contains('@')));
    expect(out, isNot(contains('phone-home')));
    expect(out, isNot(contains('-----BEGIN')));
    expect(out, isNot(matches(RegExp(r'\b\d{1,3}(\.\d{1,3}){3}\b'))));
  });
}
