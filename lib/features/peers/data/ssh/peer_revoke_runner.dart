import 'dart:typed_data';

import 'package:fav/core/errors/app_exception.dart';
import 'package:fav/core/utils/app_logger.dart';
import 'package:fav/features/install/domain/ssh_client.dart';
import 'package:fav/features/peers/data/peer_script_source.dart';
import 'package:fav/features/peers/data/ssh/peer_script_invocation.dart';
import 'package:logger/logger.dart';

/// Outcome of a `peer_revoke.sh` call.
enum PeerRevokeOutcome {
  /// The peer was removed from at least one of (wg runtime, wg0.conf).
  ok,

  /// The server reports the peer was not present (`ERR-PEER-NOT-FOUND`).
  /// The app treats this as success for the local cleanup; the calling
  /// code only surfaces the underlying [AppException] when the local
  /// removal itself fails.
  notFound,
}

/// Runs `peer_revoke.sh` over an SSH session.
class PeerRevokeRunner {
  /// Creates a [PeerRevokeRunner].
  PeerRevokeRunner({
    required this._scriptSource,
    Logger? logger,
  }) : _logger = logger ?? appLogger;

  final PeerScriptSource _scriptSource;
  final Logger _logger;

  /// Uploads `peer_revoke.sh` and runs it; returns the outcome.
  ///
  /// [overrideBytes], when set, are the user's edited version of the script
  /// and are uploaded instead of the bundled asset. The remote `/tmp`
  /// filename is keyed by a hash of the bytes actually uploaded.
  ///
  /// Throws [AppException] with [ErrorCode.peerApplyFailed] for any unknown
  /// non-zero exit code.
  Future<PeerRevokeOutcome> run({
    required SshClient ssh,
    required String password,
    required String interfaceName,
    required String peerPublicKey,
    Uint8List? overrideBytes,
    String? installationId,
    String? operationId,
  }) async {
    final scripts = await _scriptSource.load();
    final bytes = overrideBytes ?? scripts.revoke.bytes;
    final staged = await stagePeerScript(
      ssh: ssh,
      scriptName: 'peer_revoke.sh',
      bytes: bytes,
    );

    final isV2 = installationId != null;
    if (isV2) {
      await ssh.uploadBytes(
        remotePath: '${staged.dir}/peer_manager.py',
        data: scripts.manager.bytes,
      );
    }
    final env = <String, String>{
      'INTERFACE_NAME': interfaceName,
      'PEER_PUBKEY': peerPublicKey,
    };
    if (isV2) {
      env.addAll({
        'FAV_CONFIG_VERSION': '2',
        'FAV_INSTALLATION_ID': installationId,
        'FAV_OPERATION_ID': operationId!,
        'FAV_PEER_MANAGER': '${staged.dir}/peer_manager.py',
      });
    }
    final command = buildSudoEnvCommand(
      env: env,
      remotePath: staged.path,
    );
    // Terminate the sudo -S password with a newline, like every other call
    // site — relying on channel EOF is brittle across sudo builds (audit L2).
    final result = await ssh.run(command, stdin: '$password\n');
    await _cleanup(ssh, staged.dir);

    if (result.exitCode == 0) {
      return PeerRevokeOutcome.ok;
    }
    if (result.stderr.contains('ERR-PEER-NOT-FOUND')) {
      return PeerRevokeOutcome.notFound;
    }
    if (isSudoPasswordRejection(result.stderr)) {
      throw const AppException(
        ErrorCode.authInvalidCredentials,
        detail: 'sudo rejected the password; the peer script never ran',
      );
    }
    _logger.w(
      'peer_revoke.sh failed (exit ${result.exitCode}); '
      'stderr tail: ${_truncate(result.stderr)}',
    );
    throw AppException(
      ErrorCode.peerApplyFailed,
      detail: 'unknown exit ${result.exitCode}: ${_truncate(result.stderr)}',
    );
  }

  Future<void> _cleanup(SshClient ssh, String stagingDir) async {
    try {
      await ssh.run("rm -rf '$stagingDir'");
    } on Object catch (error) {
      _logger.w(
        'peer_revoke cleanup of $stagingDir failed: '
        '${error.runtimeType}',
      );
    }
  }

  String _truncate(String text) {
    final trimmed = text.trim();
    if (trimmed.length <= 200) {
      return trimmed;
    }
    return '${trimmed.substring(trimmed.length - 200)} (truncated)';
  }
}
