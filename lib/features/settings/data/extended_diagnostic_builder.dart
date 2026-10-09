import 'package:fav/features/help/data/issue_url_builder.dart';
import 'package:fav/features/settings/domain/timestamped_error.dart';
import 'package:fav/features/settings/domain/user_preferences.dart';
import 'package:meta/meta.dart';

/// Sanitized per-server summary for the diagnostic bundle. Built by the
/// caller from the existing `serverRepositoryProvider`; only the fields
/// declared here are allowed into the bundle.
@immutable
class ServerSummary {
  /// Creates a summary.
  const ServerSummary({
    required this.osFamily,
    required this.sshPort,
    required this.installState,
    required this.peerCount,
    required this.hostKeyPrefix,
  });

  /// OS family detected on the server (e.g. `ubuntu-22.04`).
  final String osFamily;

  /// SSH port used to reach the server.
  final int sshPort;

  /// Coarse install state (e.g. `installed`, `incomplete`).
  final String installState;

  /// Number of peers registered against the server.
  final int peerCount;

  /// First 8 hex chars of the host key fingerprint (deliberately
  /// truncated to avoid identifying the server). Must be exactly 8 chars
  /// or empty.
  final String hostKeyPrefix;
}

/// Sanitized install-run summary.
@immutable
class RunSummary {
  /// Creates a summary.
  const RunSummary({
    required this.runId,
    required this.outcome,
    required this.finalStep,
    required this.when,
  });

  /// UUID assigned to the run.
  final String runId;

  /// Coarse outcome (`success`, `failed`, etc.).
  final String outcome;

  /// Name of the installer step at the end (last successful or failed).
  final String finalStep;

  /// ISO-8601 UTC timestamp.
  final String when;
}

/// Pure-logic builder for the extended diagnostic bundle.
class ExtendedDiagnosticBuilder {
  /// Composes the bundle from sanitized inputs.
  static String build({
    required IssueDiagnostic base,
    required List<ServerSummary> serverSummaries,
    required List<TimestampedError> recentErrors,
    required List<RunSummary> recentRuns,
    required UserPreferences preferences,
    required bool customScriptsPresent,
    required DateTime now,
  }) {
    final lines = <String>[
      '=== FAV — Diagnostic bundle ===',
      'Generated: ${now.toUtc().toIso8601String()}',
      'App: ${base.appVersion}',
      'Platform: ${base.platform} ${base.osVersion}',
      'Locale (UI): ${base.locale}',
      'Theme: ${preferences.themeMode.name}',
      'Preferences schemaVersion: ${preferences.schemaVersion}',
      '',
      '--- Servers (${serverSummaries.length}) ---',
      for (var i = 0; i < serverSummaries.length; i++) ...[
        _serverLine(i + 1, serverSummaries[i]),
      ],
      '',
      '--- Recent error codes (last ${recentErrors.length}) ---',
      for (final e in recentErrors)
        '${e.timestamp.toUtc().toIso8601String()} ${e.codeId}',
      '',
      '--- Recent installations (last ${recentRuns.length}) ---',
      for (final r in recentRuns) _runLine(r),
      '',
      '--- Installer scripts ---',
      'Custom scripts present: $customScriptsPresent',
      '',
      '=== End ===',
    ];
    return lines.join('\n');
  }

  static String _serverLine(int index, ServerSummary s) {
    return '[$index] os=${s.osFamily} sshPort=${s.sshPort} '
        'installState=${s.installState} peers=${s.peerCount} '
        // The provider passes '' by design (the pin lives in secure
        // storage, not in Hive): print n/a instead of a bare `=`.
        'hostKeyPrefix=${s.hostKeyPrefix.isEmpty ? 'n/a' : s.hostKeyPrefix}';
  }

  static String _runLine(RunSummary r) {
    return '${r.when} run=${r.runId} outcome=${r.outcome} '
        'finalStep=${r.finalStep}';
  }
}
