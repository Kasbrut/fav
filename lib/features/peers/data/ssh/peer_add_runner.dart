import 'dart:typed_data';

import 'package:fav/core/errors/app_exception.dart';
import 'package:fav/core/utils/app_logger.dart';
import 'package:fav/features/install/domain/ssh_client.dart';
import 'package:fav/features/peers/data/peer_add_envelope_parser.dart';
import 'package:fav/features/peers/data/peer_script_source.dart';
import 'package:fav/features/peers/data/ssh/peer_script_invocation.dart';
import 'package:fav/features/peers/domain/peer_add_envelope.dart';
import 'package:fav/features/servers/domain/wireguard_installation.dart';
import 'package:logger/logger.dart';

/// Parameters needed to run `peer_add.sh` on a server.
class PeerAddRequest {
  /// Creates a [PeerAddRequest].
  const PeerAddRequest({
    required this.interfaceName,
    required this.vpnSubnet,
    required this.publicEndpoint,
    required this.wgPort,
    required this.dns,
    required this.mtu,
    required this.label,
    this.installationId,
    this.operationId,
    this.network,
  });

  /// WireGuard interface name, e.g. `wg0`.
  final String interfaceName;

  /// VPN subnet in CIDR notation, e.g. `10.13.13.0/24`.
  final String vpnSubnet;

  /// Endpoint hostname/IP for the client.conf — typically the server's public
  /// hostname or IP.
  final String publicEndpoint;

  /// WireGuard listen port.
  final int wgPort;

  /// Comma-separated DNS servers pushed to the client.
  final String dns;

  /// Tunnel MTU.
  final int mtu;

  /// User-chosen label (already validated by `isValidPeerLabel` at the call
  /// site; the server sanitises again into a `# label:` comment).
  final String label;

  /// Stable v2 installation identity; null selects the legacy protocol.
  final String? installationId;

  /// Persisted/reused idempotent v2 operation identity.
  final String? operationId;

  /// Local metadata used only to validate the returned v2 envelope.
  final NetworkConfiguration? network;
}

/// Runs `peer_add.sh` over an SSH session.
class PeerAddRunner {
  /// Creates a [PeerAddRunner].
  PeerAddRunner({
    required this._scriptSource,
    this._parser = const PeerAddEnvelopeParser(),
    Logger? logger,
  }) : _logger = logger ?? appLogger;

  final PeerScriptSource _scriptSource;
  final PeerAddEnvelopeParser _parser;
  final Logger _logger;

  /// Uploads `peer_add.sh` (if needed) and executes it against [ssh] with
  /// [request] as environment input; [password] feeds `sudo -S`.
  ///
  /// [overrideBytes], when set, are the user's edited version of the script
  /// and are uploaded instead of the bundled asset. The remote `/tmp`
  /// filename is keyed by a hash of the bytes actually uploaded, so a custom
  /// version never collides with the bundled one on the same path.
  ///
  /// Returns the parsed envelope on success. Throws [AppException] with an
  /// ERR-PEER-* code on any failure.
  Future<PeerAddEnvelope> run({
    required SshClient ssh,
    required String password,
    required PeerAddRequest request,
    Uint8List? overrideBytes,
  }) async {
    final scripts = await _scriptSource.load();
    final bytes = overrideBytes ?? scripts.add.bytes;
    final staged = await stagePeerScript(
      ssh: ssh,
      scriptName: 'peer_add.sh',
      bytes: bytes,
    );

    final isV2 = request.installationId != null;
    if (isV2) {
      await ssh.uploadBytes(
        remotePath: '${staged.dir}/peer_manager.py',
        data: scripts.manager.bytes,
      );
    }
    final env = isV2
        ? <String, String>{
            'FAV_CONFIG_VERSION': '2',
            'FAV_INSTALLATION_ID': request.installationId!,
            'FAV_OPERATION_ID': request.operationId!,
            'FAV_PEER_MANAGER': '${staged.dir}/peer_manager.py',
            'INTERFACE_NAME': request.interfaceName,
            'PEER_LABEL': request.label,
          }
        : <String, String>{
            'INTERFACE_NAME': request.interfaceName,
            'VPN_SUBNET': request.vpnSubnet,
            'PUBLIC_ENDPOINT': request.publicEndpoint,
            'WG_PORT': request.wgPort.toString(),
            'DNS': request.dns,
            'MTU': request.mtu.toString(),
            'PEER_LABEL': request.label,
          };
    final command = buildSudoEnvCommand(
      env: env,
      remotePath: staged.path,
    );
    // Terminate the sudo -S password with a newline, like every other call
    // site — relying on channel EOF is brittle across sudo builds (audit L2).
    final result = await ssh.run(command, stdin: '$password\n');
    // Best-effort cleanup; failures are logged but never re-thrown.
    await _cleanup(ssh, staged.dir);

    if (result.exitCode == 0) {
      try {
        return await _parser.parse(
          result.stdout,
          expected: isV2
              ? PeerAddEnvelopeExpectation(
                  network: request.network!,
                  operationId: request.operationId!,
                  revision: request.network!.revision! + 1,
                )
              : null,
        );
      } on AppException {
        rethrow;
      }
    }

    final stderr = result.stderr;
    if (stderr.contains('ERR-PEER-SUBNET-EXHAUSTED')) {
      throw AppException(
        ErrorCode.peerSubnetExhausted,
        detail: _truncate(stderr),
      );
    }
    if (stderr.contains('ERR-PEER-APPLY-FAILED')) {
      throw AppException(
        ErrorCode.peerApplyFailed,
        detail: _truncate(stderr),
      );
    }
    if (isSudoPasswordRejection(stderr)) {
      throw const AppException(
        ErrorCode.authInvalidCredentials,
        detail: 'sudo rejected the password; the peer script never ran',
      );
    }
    _logger.w(
      'peer_add.sh failed (exit ${result.exitCode}); '
      'stderr tail: ${_truncate(stderr)}',
    );
    throw AppException(
      ErrorCode.peerApplyFailed,
      detail: 'unknown exit ${result.exitCode}: ${_truncate(stderr)}',
    );
  }

  Future<void> _cleanup(SshClient ssh, String stagingDir) async {
    try {
      await ssh.run("rm -rf '$stagingDir'");
    } on Object catch (error) {
      _logger.w('peer_add cleanup of $stagingDir failed: ${error.runtimeType}');
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
