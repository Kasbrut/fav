import 'package:meta/meta.dart';

/// One peer reported by the server-side monitoring agent (M15).
///
/// The `endpoint` field is intentionally not stored here in serialized form
/// — it is the client's WAN IP (PII) and must stay in-memory only. See
/// [PeerSnapshot.endpointInMemory]; never serialize it.
@immutable
class PeerSnapshot {
  /// Creates a [PeerSnapshot].
  const PeerSnapshot({
    required this.publicKey,
    required this.allowedIps,
    required this.latestHandshake,
    required this.rx,
    required this.tx,
    required this.online,
    this.endpointInMemory,
  });

  /// Peer WireGuard public key, canonical standard-base64 form.
  final String publicKey;

  /// Routes allowed by the server-side config for this peer.
  final List<String> allowedIps;

  /// Unix timestamp (seconds) of the latest WG handshake; 0 means "never".
  final int latestHandshake;

  /// Total bytes received from this peer (cumulative).
  final int rx;

  /// Total bytes sent to this peer (cumulative).
  final int tx;

  /// Whether the agent considers the peer currently online (M15-T5 predicate).
  final bool online;

  /// Client WAN endpoint as reported by `wg show` (PII). NEVER serialized.
  /// Kept in memory only for diagnostics.
  final String? endpointInMemory;

  @override
  bool operator ==(Object other) {
    return other is PeerSnapshot &&
        other.publicKey == publicKey &&
        other.latestHandshake == latestHandshake &&
        other.rx == rx &&
        other.tx == tx &&
        other.online == online &&
        _listEquals(other.allowedIps, allowedIps);
    // endpointInMemory intentionally excluded from equality.
  }

  @override
  int get hashCode => Object.hash(
    publicKey,
    Object.hashAll(allowedIps),
    latestHandshake,
    rx,
    tx,
    online,
  );
}

/// A snapshot read of the agent's `peers-state.json` file (M15-T5).
@immutable
class PeersStateSnapshot {
  /// Creates a [PeersStateSnapshot].
  const PeersStateSnapshot({
    required this.generatedAt,
    required this.peers,
    this.monitorVersion,
    this.interfacePublicKey,
    this.interfaceListenPort,
  });

  /// When the agent produced this snapshot (server clock).
  final DateTime generatedAt;

  /// Peers reported in the snapshot, in agent order.
  final List<PeerSnapshot> peers;

  /// Monitor agent version (e.g. `1.0.0`).
  final String? monitorVersion;

  /// Server interface public key.
  final String? interfacePublicKey;

  /// Server interface listen port.
  final int? interfaceListenPort;
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}
