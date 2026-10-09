import 'package:fav/core/errors/app_exception.dart';
import 'package:fav/core/utils/app_logger.dart';
import 'package:fav/features/install/domain/run_paths.dart';
import 'package:fav/features/install/domain/ssh_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';
import 'package:meta/meta.dart';

/// Marker printed by `reopen_ssh.sh` on success.
const String _reopenOkMarker = 'WG-RVT-OK';

/// Outcome of running `reopen_ssh.sh`.
@immutable
sealed class ReopenSshOutcome {
  const ReopenSshOutcome();
}

/// SSH access was re-opened.
class ReopenSshApplied extends ReopenSshOutcome {
  /// Creates a [ReopenSshApplied].
  const ReopenSshApplied();
}

/// The reversal aborted (and the script rolled back); carries the reason.
class ReopenSshAborted extends ReopenSshOutcome {
  /// Creates a [ReopenSshAborted].
  const ReopenSshAborted(this.error);

  /// The failure to surface to the user (`ERR-LCK-01`).
  final AppException error;
}

/// Runs `reopen_ssh.sh` synchronously over a connected session to reverse the
/// SSH hardening, mirroring `AntiLockoutService`/`HardeningService`.
class ReopenSshService {
  /// Creates a [ReopenSshService].
  ReopenSshService({Logger? logger}) : _logger = logger ?? appLogger;

  final Logger _logger;

  /// Uploads and runs `reopen_ssh.sh` on the already-connected [client].
  ///
  /// [scriptBytes] is the integrity-verified `reopen_ssh.sh`. [sudoPassword]
  /// is piped to `sudo -S` via stdin and never appears on a command line.
  Future<ReopenSshOutcome> reopen({
    required SshClient client,
    required RunPaths paths,
    required List<int> scriptBytes,
    required String sudoPassword,
  }) async {
    final remoteScript = '/tmp/wg-rvt-${paths.runId}.sh';
    try {
      _logger.i('Re-open SSH: uploading reopen_ssh.sh');
      await client.uploadBytes(remotePath: remoteScript, data: scriptBytes);
      final result = await client.run(
        "sudo -S -p '' -- bash '$remoteScript'",
        stdin: '$sudoPassword\n',
      );
      // Best-effort cleanup of the uploaded script.
      await client.run("rm -f '$remoteScript'");
      if (result.isSuccess && result.stdout.contains(_reopenOkMarker)) {
        return const ReopenSshApplied();
      }
      // The script's stdout carries fixed, secret-free diagnostic lines.
      final detail = result.stdout.trim();
      return ReopenSshAborted(
        AppException(
          ErrorCode.lockoutAborted,
          detail: detail.isEmpty ? null : detail,
        ),
      );
    } on AppException catch (error) {
      return ReopenSshAborted(error);
    } on Object catch (error) {
      _logger.w('Re-open SSH: failed with ${error.runtimeType}');
      return const ReopenSshAborted(AppException(ErrorCode.lockoutAborted));
    }
  }
}

/// Provides the [ReopenSshService].
final Provider<ReopenSshService> reopenSshServiceProvider =
    Provider<ReopenSshService>((ref) => ReopenSshService());
