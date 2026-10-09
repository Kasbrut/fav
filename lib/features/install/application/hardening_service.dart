import 'dart:typed_data';

import 'package:fav/core/crypto/ed25519_keypair.dart';
import 'package:fav/core/errors/app_exception.dart';
import 'package:fav/core/utils/app_logger.dart';
import 'package:fav/features/install/application/anti_lockout_service.dart';
import 'package:fav/features/install/data/ssh/dart_ssh_client.dart';
import 'package:fav/features/install/domain/management_identity.dart';
import 'package:fav/features/install/domain/run_paths.dart';
import 'package:fav/features/install/domain/ssh_client.dart';
import 'package:fav/features/servers/domain/server.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';
import 'package:meta/meta.dart';

/// Marker printed by `disable_password_auth.sh` on success.
const String _hardeningOkMarker = 'WG-HRD-OK';

/// Outcome of the optional SSH hardening sequence (spec §10.3).
@immutable
sealed class HardeningOutcome {
  /// Const base constructor.
  const HardeningOutcome();
}

/// Hardening applied: key-only login proven, password auth disabled.
class HardeningApplied extends HardeningOutcome {
  /// Creates a [HardeningApplied].
  const HardeningApplied();
}

/// The sequence aborted; password auth stays enabled.
class HardeningAborted extends HardeningOutcome {
  /// Creates a [HardeningAborted].
  const HardeningAborted(this.error);

  /// The failure to surface to the user (`ERR-LCK-01` reused: same class of
  /// anti-lockout failure — a server-side hardening op that aborted safely).
  final AppException error;
}

/// Disables SSH password authentication after proving that key-based login
/// works for the management user (spec §10.3, RF-18).
///
/// Mirrors [AntiLockoutService] but authenticates via the app-generated
/// Ed25519 key instead of the password: the connect itself is the proof
/// that `authorized_keys` was set up correctly by `80_hardening.sh`. If the
/// connect fails, password auth is left untouched.
class HardeningService {
  /// Creates a [HardeningService].
  HardeningService(this._sshClientFactory, {Logger? logger})
    : _logger = logger ?? appLogger;

  final SshClient Function() _sshClientFactory;
  final Logger _logger;

  /// Runs the hardening sequence for [server], [identity] and [keyPair].
  ///
  /// [scriptBytes] is the integrity-verified `disable_password_auth.sh`.
  Future<HardeningOutcome> apply({
    required Server server,
    required ManagementIdentity identity,
    required Ed25519KeyPair keyPair,
    required RunPaths paths,
    required Uint8List scriptBytes,
  }) async {
    final dartSshIdentity = keyPair.asDartSshKeyPair(
      comment: 'fav@${server.id}',
    );
    final keyOnlyParams = SshConnectionParams(
      host: server.host,
      port: server.sshPort,
      username: identity.username,
      password: identity.password,
      identities: [dartSshIdentity],
      // Forbidding password fallback is essential — without this, a silent
      // password authentication would mask a broken `authorized_keys` and
      // we would happily disable password auth, locking the user out.
      passwordAuthAllowed: false,
    );

    final client = _sshClientFactory();
    final remoteScript = '/tmp/wg-hrd-${paths.runId}.sh';
    final password = '${identity.password}\n';
    try {
      _logger.i(
        'Hardening: connecting as the management user (key-only)',
      );
      // Key-only connect proves that 80_hardening.sh wrote authorized_keys
      // correctly. If this fails, password auth has not been disabled yet
      // and the server stays reachable as before.
      await client.connect(keyOnlyParams);
      _logger.i('Hardening: pre-reload key login verified, probing sudo');
      final sudoCheck = await client.run(
        "sudo -S -p '' -- true",
        stdin: password,
      );
      _logger.i('Hardening: sudo probe exit ${sudoCheck.exitCode}');
      if (!sudoCheck.isSuccess) {
        return const HardeningAborted(
          AppException(
            ErrorCode.lockoutAborted,
            detail: 'the management user cannot use sudo over the key session',
          ),
        );
      }
      _logger.i('Hardening: uploading disable_password_auth.sh');
      await client.uploadBytes(remotePath: remoteScript, data: scriptBytes);
      await client.run("chmod 600 '$remoteScript'");
      _logger.i('Hardening: running disable_password_auth.sh under sudo');
      final result = await client.run(
        "sudo -S -p '' -- bash '$remoteScript'",
        stdin: password,
      );
      _logger.i(
        'Hardening: script exit ${result.exitCode}; '
        'stdout: ${result.stdout.trim()}',
      );
      await client.run("rm -f '$remoteScript'");
      if (!result.isSuccess || !result.stdout.contains(_hardeningOkMarker)) {
        final detail = result.stdout.trim();
        return HardeningAborted(
          AppException(
            ErrorCode.lockoutAborted,
            detail: detail.isEmpty ? null : detail,
          ),
        );
      }
    } on HostKeyUnknownException {
      // The host key is already pinned by the first install session — an
      // "unknown" key here means the server identity changed since: treat
      // it as a connect failure, not as a fresh TOFU prompt.
      await client.close();
      return const HardeningAborted(
        AppException(
          ErrorCode.lockoutAborted,
          detail: 'key-based login could not be verified',
        ),
      );
    } on AppException catch (error) {
      await client.close();
      if (error.code == ErrorCode.hostKeyMismatch) {
        return HardeningAborted(error);
      }
      return HardeningAborted(
        AppException(
          ErrorCode.lockoutAborted,
          detail: 'key-based login could not be verified',
          cause: error,
        ),
      );
    } on Object catch (error) {
      _logger.w('Hardening: aborted with ${error.runtimeType}');
      await client.close();
      return const HardeningAborted(AppException(ErrorCode.lockoutAborted));
    }

    // Post-reload verification: open a NEW key-only session to prove that
    // key authentication still works after `PasswordAuthentication no` was
    // applied — pre-reload success only proved key auth worked with the
    // OLD config (spec §10.3 "Verify login via a working key").
    // The pre-reload session is kept open: a successful sshd reload does
    // not kill existing connections, so it remains a recovery channel.
    _logger.i('Hardening: verifying key login against the reloaded sshd');
    final verifyClient = _sshClientFactory();
    try {
      await verifyClient.connect(keyOnlyParams);
      await verifyClient.run('true');
      _logger.i('Hardening: post-reload key login verified');
      await verifyClient.close();
      await client.close();
      return const HardeningApplied();
    } on Object catch (error) {
      // The new config rejects the key session, but [client] is still
      // alive — try a best-effort rollback through it before reporting.
      _logger.e(
        'Hardening: post-reload key verification failed: '
        '${error.runtimeType}',
      );
      await verifyClient.close();
      await _attemptRollback(client, password);
      return const HardeningAborted(
        AppException(
          ErrorCode.lockoutAborted,
          detail: 'post-reload key login failed; password auth rolled back',
        ),
      );
    }
  }

  /// Best-effort rollback: restore the most recent timestamped backup of
  /// `sshd_config` left by `disable_password_auth.sh` and reload sshd.
  /// Runs through the still-alive pre-reload session, which survives the
  /// sshd reload.
  Future<void> _attemptRollback(SshClient client, String password) async {
    try {
      const command =
          r'''latest=$(ls -1t /etc/ssh/sshd_config.wg-installer.bak.* 2>/dev/null | head -1); if [ -n "$latest" ]; then cp -p "$latest" /etc/ssh/sshd_config && (systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null); fi''';
      final rollback = await client.run(
        "sudo -S -p '' -- bash -c '$command'",
        stdin: password,
      );
      _logger.w('Hardening: rollback exit ${rollback.exitCode}');
    } on Object catch (error) {
      _logger.e('Hardening: rollback failed: ${error.runtimeType}');
    } finally {
      await client.close();
    }
  }
}

/// Provides the [HardeningService].
final Provider<HardeningService> hardeningServiceProvider =
    Provider<HardeningService>(
      (ref) => HardeningService(ref.watch(sshClientFactoryProvider)),
    );
