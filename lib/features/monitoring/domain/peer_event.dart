import 'package:meta/meta.dart';

/// Type of a per-peer monitoring event (M15-T5).
enum PeerEventType {
  /// Peer became online.
  connect,

  /// Peer became offline.
  disconnect,
}

/// A connect/disconnect event emitted by the server-side monitor agent.
///
/// Carries the server-side timestamp — the only clock we trust for the
/// 7-day retention window. The agent never emits the client endpoint into
/// the JSONL log, so [PeerEvent] cannot carry PII (M15 design constraint).
@immutable
class PeerEvent {
  /// Creates a [PeerEvent].
  const PeerEvent({
    required this.serverId,
    required this.peerPublicKey,
    required this.type,
    required this.serverTimestamp,
    required this.rx,
    required this.tx,
    required this.latestHandshake,
  });

  /// Identifier of the server this event belongs to.
  final String serverId;

  /// Peer public key (canonical standard-base64).
  final String peerPublicKey;

  /// connect or disconnect.
  final PeerEventType type;

  /// Server-side ISO-8601 UTC timestamp.
  final DateTime serverTimestamp;

  /// Cumulative bytes RX at the moment of the event.
  final int rx;

  /// Cumulative bytes TX at the moment of the event.
  final int tx;

  /// Unix seconds of the last handshake at the moment of the event;
  /// 0 means "never seen".
  final int latestHandshake;

  /// Stable composite key used by the Hive box (M15-T4).
  String get storageKey =>
      '$serverId:$peerPublicKey:${serverTimestamp.toUtc().toIso8601String()}';

  /// Map representation written to Hive. Endpoint is never present here.
  Map<String, Object> toMap() => <String, Object>{
    'serverId': serverId,
    'peerPublicKey': peerPublicKey,
    'type': type.name,
    'serverTimestamp': serverTimestamp.toUtc().toIso8601String(),
    'rx': rx,
    'tx': tx,
    'latestHandshake': latestHandshake,
  };

  /// Reconstructs a [PeerEvent] from a Hive map. Returns `null` when the
  /// row is missing required fields — callers prune it.
  static PeerEvent? fromMap(Map<dynamic, dynamic> map) {
    final serverId = map['serverId'];
    final peerPublicKey = map['peerPublicKey'];
    final typeName = map['type'];
    final serverTimestampRaw = map['serverTimestamp'];
    if (serverId is! String ||
        peerPublicKey is! String ||
        typeName is! String ||
        serverTimestampRaw is! String) {
      return null;
    }
    final type = PeerEventType.values.firstWhere(
      (value) => value.name == typeName,
      orElse: () => PeerEventType.disconnect,
    );
    final serverTimestamp = DateTime.tryParse(serverTimestampRaw);
    if (serverTimestamp == null) {
      return null;
    }
    return PeerEvent(
      serverId: serverId,
      peerPublicKey: peerPublicKey,
      type: type,
      serverTimestamp: serverTimestamp,
      rx: (map['rx'] as num?)?.toInt() ?? 0,
      tx: (map['tx'] as num?)?.toInt() ?? 0,
      latestHandshake: (map['latestHandshake'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is PeerEvent &&
        other.serverId == serverId &&
        other.peerPublicKey == peerPublicKey &&
        other.type == type &&
        other.serverTimestamp == serverTimestamp &&
        other.rx == rx &&
        other.tx == tx &&
        other.latestHandshake == latestHandshake;
  }

  @override
  int get hashCode => Object.hash(
    serverId,
    peerPublicKey,
    type,
    serverTimestamp,
    rx,
    tx,
    latestHandshake,
  );
}
