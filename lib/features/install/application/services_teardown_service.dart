import 'dart:convert';

import 'package:fav/core/errors/app_exception.dart';
import 'package:fav/core/utils/app_logger.dart';
import 'package:fav/core/utils/shell_quote.dart';
import 'package:fav/features/install/data/scripts/asset_script_repository.dart';
import 'package:fav/features/install/domain/run_paths.dart';
import 'package:fav/features/install/domain/script_source.dart';
import 'package:fav/features/install/domain/ssh_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';
import 'package:meta/meta.dart';
import 'package:uuid/uuid.dart';

/// Marker `teardown_wireguard.sh` prints on stdout when every step succeeded.
const String _teardownOkMarker = 'WG-TRD-OK';

/// Marker the staging command echoes once the run directory exists.
const String _stagedMarker = 'WG-TRD-STAGED';

/// Outcome of running the services teardown.
@immutable
sealed class ServicesTeardownOutcome {
  /// Const base constructor.
  const ServicesTeardownOutcome();
}

/// The services teardown completed successfully.
class ServicesTeardownApplied extends ServicesTeardownOutcome {
  /// Creates a [ServicesTeardownApplied].
  const ServicesTeardownApplied();
}

/// The services teardown aborted; carries the reason.
class ServicesTeardownAborted extends ServicesTeardownOutcome {
  /// Creates a [ServicesTeardownAborted].
  const ServicesTeardownAborted(this.error);

  /// The failure to surface to the user (`ERR-TRD-01`).
  final AppException error;
}

/// Runs the services teardown synchronously over a connected session.
///
/// Unlike the old detached provisioner, this stages the teardown bundle in a
/// user-writable `/tmp` directory (no `/opt`, no root-owned state files) and
/// runs the orchestrator under `sudo -S` when the login user is not root. This
/// works on a hardened server where root login is disabled and the app
/// connects as a non-root sudoer. Mirrors `ReopenSshService` /
/// `MonitoringInstallService`.
class ServicesTeardownService {
  /// Creates a [ServicesTeardownService].
  ServicesTeardownService({Logger? logger}) : _logger = logger ?? appLogger;

  final Logger _logger;

  /// Stages and runs the teardown on the already-connected [client].
  ///
  /// [bundle] is the integrity-verified script bundle; the orchestrator,
  /// `lib/common.sh` and the teardown modules are picked from it.
  /// [interfaceName] and [vpnSubnet] are written to `config.env`. When
  /// [sudoPassword] is given it is piped to `sudo -S` via stdin and never
  /// appears on a command line; when null, the orchestrator is run directly
  /// (login user is root).
  Future<ServicesTeardownOutcome> run({
    required SshClient client,
    required ScriptBundle bundle,
    required String interfaceName,
    required String vpnSubnet,
    String? sudoPassword,
    bool sweepInstallerDirs = true,
  }) async {
    final stagingDir = '/tmp/wg-trd-${const Uuid().v4()}';
    try {
      _logger.i('Services teardown: staging assets in $stagingDir');
      final staged = await client.run(
        "rm -rf '$stagingDir' && mkdir -p "
        "'$stagingDir/lib' '$stagingDir/teardown/modules' && "
        "printf '$_stagedMarker\\n'",
      );
      // Check the stdout marker, NOT the exit code: this command has no stdin,
      // so dartssh2 runs it over the plain exec channel, which reports no exit
      // code (-1) on OpenSSH >= 10 even when the command succeeded. stdout is
      // still captured, so the marker is the reliable signal.
      if (!staged.stdout.contains(_stagedMarker)) {
        return const ServicesTeardownAborted(
          AppException(
            ErrorCode.teardownFailed,
            detail: 'failed to create the teardown staging directory',
          ),
        );
      }

      // Upload the orchestrator, the shared library and the numbered modules.
      await _upload(
        client,
        bundle,
        kTeardownOrchestratorScript,
        '$stagingDir/teardown_wireguard.sh',
      );
      await _upload(
        client,
        bundle,
        'lib/common.sh',
        '$stagingDir/lib/common.sh',
      );
      await _upload(
        client,
        bundle,
        'lib/firewall_manager.py',
        '$stagingDir/lib/firewall_manager.py',
      );
      for (final relPath in kTeardownModuleManifest) {
        final basename = relPath.split('/').last;
        await _upload(
          client,
          bundle,
          relPath,
          '$stagingDir/teardown/modules/$basename',
        );
      }

      // Write the minimal parameters file the teardown modules read.
      final config =
          'INTERFACE_NAME=${shellSingleQuote(interfaceName)}\n'
          'VPN_SUBNET=${shellSingleQuote(vpnSubnet)}\n';
      await client.uploadBytes(
        remotePath: '$stagingDir/config.env',
        data: utf8.encode(config),
      );

      _logger.i(
        'Services teardown: running orchestrator '
        '(${sudoPassword == null ? "direct" : "sudo"})',
      );
      final SshCommandResult result;
      if (sudoPassword == null) {
        result = await client.run(
          "bash '$stagingDir/teardown_wireguard.sh' '$stagingDir'",
        );
      } else {
        result = await client.run(
          "sudo -S -p '' -- bash '$stagingDir/teardown_wireguard.sh' "
          "'$stagingDir'",
          stdin: '$sudoPassword\n',
        );
      }
      _logger.i('Services teardown: exit ${result.exitCode}');

      // Best-effort staging dir cleanup.
      await client.run("rm -rf '$stagingDir'");

      // Success is the orchestrator's stdout marker, not the SSH exit code —
      // `set -e` aborts the script before the marker on any failure, and this
      // is robust to the no-exit-code (-1) plain-exec case described above
      // (matches reopen WG-RVT-OK / hardening WG-HRD-OK).
      if (result.stdout.contains(_teardownOkMarker)) {
        if (sweepInstallerDirs) {
          await _sweepInstallerDirs(client, sudoPassword);
        }
        return const ServicesTeardownApplied();
      }
      final detail = result.stderr.trim().isNotEmpty
          ? result.stderr.trim()
          : result.stdout.trim();
      return ServicesTeardownAborted(
        AppException(
          ErrorCode.teardownFailed,
          detail: detail.isEmpty ? null : detail,
        ),
      );
    } on AppException catch (error) {
      return ServicesTeardownAborted(error);
    } on Object catch (error) {
      // Never log the raw error/stack — remote stderr can carry user content.
      _logger.w('Services teardown: unexpected failure ${error.runtimeType}');
      return ServicesTeardownAborted(
        AppException(
          ErrorCode.teardownFailed,
          detail: 'services teardown threw ${error.runtimeType}',
        ),
      );
    }
  }

  /// Removes the FAV-owned installer directories — old run dirs, state/exit/
  /// pid files (including this teardown's own) and logs. Only after a
  /// verified teardown: on failure they stay for diagnostics (audit F3).
  /// Best-effort; the dirs are root-owned, so a sudoer login elevates.
  Future<void> _sweepInstallerDirs(
    SshClient client,
    String? sudoPassword,
  ) async {
    const sweep =
        "rm -rf '${RunPaths.runRoot}' "
        "'${RunPaths.stateDir}' '${RunPaths.logDir}'";
    try {
      if (sudoPassword == null) {
        await client.run(sweep);
      } else {
        await client.run(
          "sudo -S -p '' -- sh -c ${shellSingleQuote(sweep)}",
          stdin: '$sudoPassword\n',
        );
      }
    } on Object catch (error) {
      // The teardown itself succeeded; never fail it over leftover files.
      _logger.w('Installer-dir sweep failed: ${error.runtimeType}');
    }
  }

  Future<void> _upload(
    SshClient client,
    ScriptBundle bundle,
    String relativePath,
    String remotePath,
  ) async {
    final asset = bundle.assets.firstWhere(
      (entry) => entry.relativePath == relativePath,
      orElse: () => throw const AppException(
        ErrorCode.scriptInvalid,
        detail: 'teardown bundle is missing one of the required assets',
      ),
    );
    await client.uploadBytes(remotePath: remotePath, data: asset.bytes);
  }
}

/// Provides the [ServicesTeardownService].
final Provider<ServicesTeardownService> servicesTeardownServiceProvider =
    Provider<ServicesTeardownService>((ref) => ServicesTeardownService());
