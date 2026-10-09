import 'dart:typed_data';

import 'package:fav/core/errors/app_exception.dart';
import 'package:fav/core/utils/app_logger.dart';
import 'package:fav/features/install/data/ssh/dart_ssh_client.dart';
import 'package:fav/features/install/domain/management_identity.dart';
import 'package:fav/features/install/domain/run_paths.dart';
import 'package:fav/features/install/domain/ssh_client.dart';
import 'package:fav/features/servers/domain/server.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';
import 'package:meta/meta.dart';

/// Marker printed by `disable_root_ssh.sh` on success.
const String _lockoutOkMarker = 'WG-LCK-OK';

/// Outcome of the anti-lockout root-SSH-disable sequence (spec §10.2).
@immutable
sealed class AntiLockoutOutcome {
  /// Const base constructor.
  const AntiLockoutOutcome();
}

/// Root SSH login was disabled successfully.
class AntiLockoutDisabled extends AntiLockoutOutcome {
  /// Creates an [AntiLockoutDisabled].
  const AntiLockoutDisabled();
}

/// The sequence aborted; root SSH stays enabled and the server is reachable.
class AntiLockoutAborted extends AntiLockoutOutcome {
  /// Creates an [AntiLockoutAborted].
  const AntiLockoutAborted(this.error);

  /// The failure to surface to the user (`ERR-LCK-01`).
  final AppException error;
}

/// Disables root SSH login from a second SSH session as the management user.
///
/// Implements spec §10.2 steps 3-10: the connect proves the management user
/// in, a `sudo` probe proves privilege escalation works, then the reviewed
/// `disable_root_ssh.sh` performs the dry-run + backup + reload + rollback.
/// Any anomaly leaves the server reachable as root.
class AntiLockoutService {
  /// Creates an [AntiLockoutService].
  AntiLockoutService(this._sshClientFactory, {Logger? logger})
    : _logger = logger ?? appLogger;

  final SshClient Function() _sshClientFactory;
  final Logger _logger;

  /// Runs the anti-lockout sequence for [server] and [identity].
  ///
  /// [scriptBytes] is the integrity-verified `disable_root_ssh.sh`.
  Future<AntiLockoutOutcome> disableRootSsh({
    required Server server,
    required ManagementIdentity identity,
    required RunPaths paths,
    required Uint8List scriptBytes,
  }) async {
    final client = _sshClientFactory();
    final remoteScript = '/tmp/wg-lck-${paths.runId}.sh';
    // The password is fed to `sudo -S` on stdin: never an argv or a log line.
    final password = '${identity.password}\n';
    try {
      // §10.2 step 3: the connect itself proves the management user's login.
      _logger.i('Anti-lockout: connecting as the management user');
      await client.connect(
        SshConnectionParams(
          host: server.host,
          port: server.sshPort,
          username: identity.username,
          password: identity.password,
        ),
      );
      _logger.i('Anti-lockout: connected, probing sudo');
      // §10.2 step 4: prove the management user can use sudo.
      final sudoCheck = await client.run(
        "sudo -S -p '' -- true",
        stdin: password,
      );
      _logger.i(
        'Anti-lockout: sudo probe exit ${sudoCheck.exitCode}; '
        'stderr: ${sudoCheck.stderr.trim()}',
      );
      if (!sudoCheck.isSuccess) {
        return const AntiLockoutAborted(
          AppException(
            ErrorCode.lockoutAborted,
            detail: 'the management user cannot use sudo',
          ),
        );
      }
      // §10.2 steps 5-10: run the reviewed disable script under sudo.
      _logger.i('Anti-lockout: uploading disable script');
      await client.uploadBytes(remotePath: remoteScript, data: scriptBytes);
      _logger.i('Anti-lockout: running disable script under sudo');
      await client.run("chmod 600 '$remoteScript'");
      final result = await client.run(
        "sudo -S -p '' -- bash '$remoteScript'",
        stdin: password,
      );
      _logger.i(
        'Anti-lockout: script exit ${result.exitCode}; '
        'stdout: ${result.stdout.trim()}; '
        'stderr: ${result.stderr.trim()}',
      );
      await client.run("rm -f '$remoteScript'");
      if (result.isSuccess && result.stdout.contains(_lockoutOkMarker)) {
        return const AntiLockoutDisabled();
      }
      // The script's stdout carries fixed, secret-free diagnostic lines.
      final detail = result.stdout.trim();
      return AntiLockoutAborted(
        AppException(
          ErrorCode.lockoutAborted,
          detail: detail.isEmpty ? null : detail,
        ),
      );
    } on HostKeyUnknownException {
      return const AntiLockoutAborted(
        AppException(
          ErrorCode.lockoutAborted,
          detail: 'the management user login could not be verified',
        ),
      );
    } on AppException catch (error) {
      // A changed host key is a possible MITM — surface it as ERR-HOST-01,
      // never as a generic login failure.
      if (error.code == ErrorCode.hostKeyMismatch) {
        return AntiLockoutAborted(error);
      }
      // Failing to connect as the management user means its login is broken.
      return AntiLockoutAborted(
        AppException(
          ErrorCode.lockoutAborted,
          detail: 'the management user login could not be verified',
          cause: error,
        ),
      );
    } on Object catch (error) {
      _logger.w('Anti-lockout: aborted with ${error.runtimeType}');
      return const AntiLockoutAborted(
        AppException(ErrorCode.lockoutAborted),
      );
    } finally {
      await client.close();
    }
  }
}

/// Provides the [AntiLockoutService].
final Provider<AntiLockoutService> antiLockoutServiceProvider =
    Provider<AntiLockoutService>(
      (ref) => AntiLockoutService(ref.watch(sshClientFactoryProvider)),
    );
