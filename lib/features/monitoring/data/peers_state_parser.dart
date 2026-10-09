import 'dart:convert';

import 'package:fav/features/monitoring/domain/peer_snapshot.dart';

/// Parses the JSON snapshot file written by the server monitor agent
/// (M15-T2: `/var/lib/fav/peers-state.json`).
class PeersStateParser {
  /// Creates a [PeersStateParser].
  const PeersStateParser();

  /// Parses [content] into a [PeersStateSnapshot].
  ///
  /// Returns `null` when:
  ///   - the input is empty / truncated / not JSON, or
  ///   - the `schemaVersion` is not 1, or
  ///   - `generatedAt` is missing or malformed.
  ///
  /// Forward-compat behavior — unknown extra fields are ignored, peers with
  /// malformed entries are skipped, never the whole snapshot.
  PeersStateSnapshot? tryParse(String content) {
    if (content.trim().isEmpty) {
      return null;
    }
    final dynamic decoded;
    try {
      decoded = jsonDecode(content);
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, dynamic>) {
      return null;
    }
    if (decoded['schemaVersion'] != 1) {
      return null;
    }
    final generatedAtRaw = decoded['generatedAt'];
    if (generatedAtRaw is! String) {
      return null;
    }
    final generatedAt = DateTime.tryParse(generatedAtRaw);
    if (generatedAt == null) {
      return null;
    }

    String? interfacePublicKey;
    int? interfaceListenPort;
    final iface = decoded['interface'];
    if (iface is Map<String, dynamic>) {
      final pk = iface['publicKey'];
      final port = iface['listenPort'];
      interfacePublicKey = pk is String && pk.isNotEmpty ? pk : null;
      interfaceListenPort = port is num ? port.toInt() : null;
    }

    final peers = <PeerSnapshot>[];
    final peersRaw = decoded['peers'];
    if (peersRaw is List) {
      for (final entry in peersRaw) {
        if (entry is! Map<String, dynamic>) {
          continue;
        }
        final publicKey = entry['publicKey'];
        if (publicKey is! String || publicKey.isEmpty) {
          continue;
        }
        final allowedIps = <String>[];
        final allowedRaw = entry['allowedIps'];
        if (allowedRaw is List) {
          for (final ip in allowedRaw) {
            if (ip is String && ip.isNotEmpty) {
              allowedIps.add(ip);
            }
          }
        }
        final endpoint = entry['endpoint'];
        peers.add(
          PeerSnapshot(
            publicKey: publicKey,
            allowedIps: allowedIps,
            latestHandshake: (entry['latestHandshake'] as num?)?.toInt() ?? 0,
            rx: (entry['rx'] as num?)?.toInt() ?? 0,
            tx: (entry['tx'] as num?)?.toInt() ?? 0,
            online: entry['online'] == true,
            endpointInMemory: endpoint is String && endpoint.isNotEmpty
                ? endpoint
                : null,
          ),
        );
      }
    }

    final monitorVersionRaw = decoded['monitorVersion'];
    return PeersStateSnapshot(
      generatedAt: generatedAt,
      peers: peers,
      monitorVersion: monitorVersionRaw is String ? monitorVersionRaw : null,
      interfacePublicKey: interfacePublicKey,
      interfaceListenPort: interfaceListenPort,
    );
  }
}
