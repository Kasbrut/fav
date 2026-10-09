import 'dart:convert';

import 'package:fav/core/crypto/sha256_hasher.dart';
import 'package:fav/features/install/domain/script_source.dart';
import 'package:flutter/services.dart' show AssetBundle, rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Relative paths of every bundled installer script, in upload order.
const List<String> kScriptManifest = [
  'install_wireguard.sh',
  'lib/common.sh',
  'lib/firewall_manager.py',
  'lib/network_probe.py',
  'lib/profile_renderer.py',
  'modules/00_probe.sh',
  'modules/10_install_pkgs.sh',
  'modules/15_network_probe.sh',
  'modules/20_create_user.sh',
  'modules/25_deploy_app_key.sh',
  'modules/26_deploy_user_keys.sh',
  'modules/30_generate_keys.sh',
  'modules/40_write_server_conf.sh',
  'modules/45_firewall_guard.sh',
  'modules/50_enable_forwarding.sh',
  'modules/60_firewall.sh',
  'modules/70_start_service.sh',
  'modules/80_hardening.sh',
  'modules/90_health_check.sh',
  'modules/99_finalize.sh',
  'disable_root_ssh.sh',
  'disable_password_auth.sh',
  // M15-T2: monitoring agent bundle. Uploaded by the install flow in a
  // dedicated session, like the anti-lockout / hardening scripts above.
  'install_monitor.sh',
  'wg-monitor.sh',
  'lib/wg-monitor.service',
  'lib/wg-monitor.timer',
  'lib/wg-monitor.logrotate',
  // Teardown bundle (Phase 1). Staged in /tmp by ServicesTeardownService,
  // never with the install scripts.
  'teardown_wireguard.sh',
  'teardown/modules/10_stop_service.sh',
  'teardown/modules/20_remove_monitor.sh',
  'teardown/modules/30_remove_firewall.sh',
  'teardown/modules/40_remove_forwarding.sh',
  'teardown/modules/50_remove_config.sh',
  'teardown/modules/60_remove_fail2ban_jail.sh',
  'reopen_ssh.sh',
];

/// Relative path of the orchestrator script — the installer entry point
/// shown and edited in the script editor (spec §6.3).
const String kOrchestratorScript = 'install_wireguard.sh';

/// Relative path of the standalone root-SSH-disable script (spec §10.2).
///
/// It belongs to the integrity-verified bundle but is NOT uploaded with the
/// install scripts — the anti-lockout flow uploads it on its own from a
/// second SSH session.
const String kAntiLockoutScript = 'disable_root_ssh.sh';

/// Relative path of the standalone hardening script that disables SSH
/// password authentication (spec §10.3).
///
/// Bundled and integrity-verified, but uploaded by the hardening flow from a
/// dedicated key-based SSH session — not with the install scripts.
const String kDisablePasswordAuthScript = 'disable_password_auth.sh';

/// Relative path of the standalone monitoring installer (M15-T2). Uploaded
/// by the monitoring-install flow in a dedicated SSH session, not by the
/// main provisioner — it lives outside the per-run script directory.
const String kMonitorInstallScript = 'install_monitor.sh';

/// Relative path of the peer-snapshot agent that runs on the server every
/// 30s via the systemd timer (M15-T2).
const String kMonitorAgentScript = 'wg-monitor.sh';

/// Relative path of the systemd service unit that invokes the agent.
const String kMonitorServiceUnit = 'lib/wg-monitor.service';

/// Relative path of the systemd timer that fires the agent every 30s.
const String kMonitorTimerUnit = 'lib/wg-monitor.timer';

/// Relative path of the logrotate config that bounds the events log to 7
/// daily rotations (safety net on top of the in-script 7-day trim).
const String kMonitorLogrotateConfig = 'lib/wg-monitor.logrotate';

/// Convenience set used by the provisioner to exclude monitor assets from
/// the per-run upload.
const Set<String> kMonitorBundleAssets = {
  kMonitorInstallScript,
  kMonitorAgentScript,
  kMonitorServiceUnit,
  kMonitorTimerUnit,
  kMonitorLogrotateConfig,
};

/// Relative path of the teardown orchestrator (Phase 1). Staged in /tmp by
/// ServicesTeardownService, never with the installer.
const String kTeardownOrchestratorScript = 'teardown_wireguard.sh';

/// Relative path of the standalone SSH-hardening reversal script. Uploaded by
/// the teardown flow from a dedicated session, like the disable scripts.
const String kReopenSshScript = 'reopen_ssh.sh';

/// Teardown service modules, in run order.
const List<String> kTeardownModuleManifest = [
  'teardown/modules/10_stop_service.sh',
  'teardown/modules/20_remove_monitor.sh',
  'teardown/modules/30_remove_firewall.sh',
  'teardown/modules/40_remove_forwarding.sh',
  'teardown/modules/50_remove_config.sh',
  'teardown/modules/60_remove_fail2ban_jail.sh',
];

/// Assets that belong to the teardown flow and must be excluded from the
/// install-time upload (mirrors [kMonitorBundleAssets]).
const Set<String> kTeardownBundleAssets = {
  kTeardownOrchestratorScript,
  kReopenSshScript,
  ...kTeardownModuleManifest,
};

/// Asset directory (declared in `pubspec.yaml`) holding the bundled scripts.
const String _assetRoot = 'lib/assets/scripts';

/// Computes the canonical SHA-256 over a set of scripts.
///
/// For each asset (sorted by path) the line `<path>\n<fileHash>\n` is built;
/// the lines are concatenated and hashed once, so both the file contents and
/// the set of paths affect the result.
String canonicalBundleHash(List<ScriptAsset> assets) {
  final sorted = [...assets]
    ..sort((a, b) => a.relativePath.compareTo(b.relativePath));
  final buffer = StringBuffer();
  for (final asset in sorted) {
    buffer
      ..write(asset.relativePath)
      ..write('\n')
      ..write(sha256Hex(asset.bytes))
      ..write('\n');
  }
  return sha256Hex(utf8.encode(buffer.toString()));
}

/// Loads the installer scripts bundled with the app as Flutter assets.
class AssetScriptRepository {
  /// Creates an [AssetScriptRepository] reading from [bundle].
  ///
  /// [bundle] defaults to [rootBundle]; tests pass a fake asset bundle.
  AssetScriptRepository({AssetBundle? bundle}) : _bundle = bundle ?? rootBundle;

  final AssetBundle _bundle;

  /// Loads every bundled script and returns them with the canonical hash.
  Future<ScriptBundle> loadDefaultBundle() async {
    final assets = <ScriptAsset>[];
    for (final relativePath in kScriptManifest) {
      final data = await _bundle.load('$_assetRoot/$relativePath');
      assets.add(
        ScriptAsset(
          relativePath: relativePath,
          bytes: data.buffer.asUint8List(
            data.offsetInBytes,
            data.lengthInBytes,
          ),
        ),
      );
    }
    assets.sort((a, b) => a.relativePath.compareTo(b.relativePath));
    return ScriptBundle(
      assets: assets,
      bundleHash: canonicalBundleHash(assets),
    );
  }
}

/// Provides the [AssetScriptRepository] backed by the app's asset bundle.
final Provider<AssetScriptRepository> scriptRepositoryProvider =
    Provider<AssetScriptRepository>((ref) => AssetScriptRepository());
