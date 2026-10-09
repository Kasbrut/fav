import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:fav/core/persistence/app_database.dart';
import 'package:fav/features/help/application/recent_errors_provider.dart';
import 'package:fav/features/help/data/issue_url_builder.dart';
import 'package:fav/features/settings/application/preferences_controller.dart';
import 'package:fav/features/settings/data/extended_diagnostic_builder.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Async builder of the extended-diagnostics bundle string.
typedef DiagnosticFn = Future<String> Function({Locale? uiLocale});

/// Returns an async function that builds the bundle string from the live
/// app state at call time. Resolves [PackageInfo], [DeviceInfoPlugin] and
/// the active UI locale every invocation; failures fall back to `'unknown'`.
///
/// Sanitization contract: only allowlisted non-identifying fields enter
/// [ExtendedDiagnosticBuilder]. Specifically:
///   - Server IP / hostname / username: NOT included.
///   - Host key: only the first 8 hex characters of the fingerprint; the
///     fingerprint itself lives in secure storage and is NOT accessed here.
///   - Passwords / private keys: never stored in Hive, so never reachable.
final Provider<DiagnosticFn>
extendedDiagnosticProvider = Provider<DiagnosticFn>((ref) {
  return ({Locale? uiLocale}) async {
    // Resolve plugin-backed values defensively (channels may be missing in
    // tests or pre-rebuild iOS).
    var appVersion = 'unknown';
    try {
      final pkg = await PackageInfo.fromPlatform();
      appVersion = '${pkg.version}+${pkg.buildNumber}';
    } on Object {
      // keep 'unknown'
    }
    var osVersion = 'unknown';
    try {
      final info = DeviceInfoPlugin();
      if (Platform.isIOS) {
        osVersion = (await info.iosInfo).systemVersion;
      } else if (Platform.isAndroid) {
        osVersion = (await info.androidInfo).version.release;
      }
    } on Object {
      // keep 'unknown'
    }
    final localeStr = _formatLocale(uiLocale);

    final prefs = ref.read(preferencesControllerProvider);
    final database = ref.read(appDatabaseProvider);

    final base = IssueDiagnostic(
      appVersion: appVersion,
      platform: Platform.operatingSystem,
      osVersion: osVersion,
      locale: localeStr,
      recentErrorCodes: ref.read(recentErrorsProvider),
    );

    // --- Server summaries -------------------------------------------------
    // Actual server box fields (server_mappers.dart):
    //   id (String), sshPort (int), metadata? (Map), installation? (Map)
    //
    // osFamily  → metadata['osId'] if metadata is present, else 'unknown'.
    //             There is no top-level 'osFamily' key; OS info lives in the
    //             optional probed metadata sub-map.
    // installState → 'installed' when the 'installation' sub-map is present
    //                and non-null, otherwise 'not_installed'.  There is no
    //                explicit install-state field on the server row.
    // hostKeyPrefix → host key fingerprints live in flutter_secure_storage
    //                 (spec §4.2), NOT in the Hive box.  Falls back to ''.
    final servers = <ServerSummary>[];
    for (final raw in database.serversBox.values) {
      final serverId = _safeString(raw, ['id']) ?? '';
      final sshPort = _safeInt(raw, ['sshPort']) ?? 0;

      // OS family: nested under metadata.osId (e.g. "ubuntu", "debian").
      final metadata = raw['metadata'];
      final osFamily = metadata is Map
          ? (_safeString(metadata, ['osId']) ?? 'unknown')
          : 'unknown';

      // Install state: derived from presence of the 'installation' sub-map.
      final installation = raw['installation'];
      final installState = (installation is Map)
          ? 'installed'
          : 'not_installed';

      // Host key fingerprint is in secure storage, not in Hive.
      const hostKeyPrefix = '';

      servers.add(
        ServerSummary(
          osFamily: osFamily,
          sshPort: sshPort,
          installState: installState,
          peerCount: _peerCountFor(serverId, database),
          hostKeyPrefix: hostKeyPrefix,
        ),
      );
    }

    // --- Run summaries ----------------------------------------------------
    // Actual runs box fields (run_mappers.dart):
    //   runId (String), status (String), steps (List<Map>), startedAt (String)
    //
    // outcome   → 'status' field (RunStatus.name: queued/running/success/
    //             failed/orphaned).
    // finalStep → key of the last step in the 'steps' list.  The steps list
    //             is ordered; the last element reflects the furthest point
    //             reached.  Falls back to 'unknown' if steps is empty or
    //             absent.
    // when      → 'startedAt' (ISO-8601 String).
    final runs = <RunSummary>[];
    for (final raw in database.runsBox.values) {
      final runId = _safeString(raw, ['runId']) ?? 'unknown';
      final outcome = _safeString(raw, ['status']) ?? 'unknown';
      final when = _safeString(raw, ['startedAt']) ?? 'unknown';

      // Derive finalStep from the last step's 'key' field.
      final rawSteps = raw['steps'];
      var finalStep = 'unknown';
      if (rawSteps is List && rawSteps.isNotEmpty) {
        final lastStep = rawSteps.last;
        if (lastStep is Map) {
          finalStep = _safeString(lastStep, ['key']) ?? 'unknown';
        }
      }

      runs.add(
        RunSummary(
          runId: runId,
          outcome: outcome,
          finalStep: finalStep,
          when: when,
        ),
      );
    }

    runs.sort((a, b) => b.when.compareTo(a.when));
    final lastFive = runs.length > 5 ? runs.sublist(0, 5) : runs;

    return ExtendedDiagnosticBuilder.build(
      base: base,
      serverSummaries: servers,
      recentErrors: prefs.recentErrors,
      recentRuns: lastFive,
      preferences: prefs,
      customScriptsPresent: database.scriptsBox.isNotEmpty,
      now: DateTime.now(),
    );
  };
});

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

String _formatLocale(Locale? l) {
  if (l == null) return 'unknown';
  final country = l.countryCode;
  return (country == null || country.isEmpty)
      ? l.languageCode
      : '${l.languageCode}_$country';
}

/// Returns the first non-empty [String] value found under any of [keys], or
/// `null` when none matches.
String? _safeString(Map<dynamic, dynamic> raw, List<String> keys) {
  for (final k in keys) {
    final v = raw[k];
    if (v is String && v.isNotEmpty) return v;
  }
  return null;
}

/// Returns the first [int] value found under any of [keys], or `null`.
int? _safeInt(Map<dynamic, dynamic> raw, List<String> keys) {
  for (final k in keys) {
    final v = raw[k];
    if (v is int) return v;
  }
  return null;
}

/// Counts peers in the peers box whose `serverId` matches [serverId].
int _peerCountFor(String serverId, AppDatabase database) {
  if (serverId.isEmpty) return 0;
  var count = 0;
  for (final raw in database.peersBox.values) {
    if (raw['serverId'] == serverId) count++;
  }
  return count;
}
