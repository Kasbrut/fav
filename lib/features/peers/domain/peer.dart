import 'package:meta/meta.dart';

/// A WireGuard peer managed by the app for a specific server.
///
/// This is the canonical app-side identity of a peer: stable id, label,
/// allocated tunnel address and the public key used to correlate live
/// status against the monitoring agent's snapshot. The matching `.conf`
/// (with the private key and PSK) lives in `flutter_secure_storage`
/// under `client_profile:<id>` — never on this object.
@immutable
class Peer {
  /// Creates a [Peer].
  const Peer({
    required this.id,
    required this.serverId,
    required this.label,
    required this.address,
    required this.publicKey,
    required this.createdAt,
    this.ipv6Address,
  });

  /// Local unique identifier (UUID v4).
  final String id;

  /// Identifier of the server this peer belongs to.
  final String serverId;

  /// Human-readable name chosen by the user. Editable post-creation
  /// without any server-side operation.
  final String label;

  /// Tunnel address with CIDR mask, for example `10.13.13.3/32`.
  final String address;

  /// Explicit IPv4 tunnel address. Falls back to legacy [address].
  String get ipv4Address => address;

  /// Explicit IPv6 tunnel address, when the peer is dual-stack.
  final String? ipv6Address;

  /// The peer's public key, used for correlation with the monitoring
  /// agent's `wg show <iface> dump` snapshot and as the natural id of
  /// the runtime peer entry on the server.
  final String publicKey;

  /// When the peer was created locally.
  final DateTime createdAt;

  /// Returns a copy of this peer with the given fields replaced.
  Peer copyWith({
    String? id,
    String? serverId,
    String? label,
    String? address,
    String? ipv6Address,
    bool clearIpv6Address = false,
    String? publicKey,
    DateTime? createdAt,
  }) {
    return Peer(
      id: id ?? this.id,
      serverId: serverId ?? this.serverId,
      label: label ?? this.label,
      address: address ?? this.address,
      ipv6Address: clearIpv6Address ? null : (ipv6Address ?? this.ipv6Address),
      publicKey: publicKey ?? this.publicKey,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is Peer &&
        other.id == id &&
        other.serverId == serverId &&
        other.label == label &&
        other.address == address &&
        other.ipv6Address == ipv6Address &&
        other.publicKey == publicKey &&
        other.createdAt == createdAt;
  }

  @override
  int get hashCode => Object.hash(
    id,
    serverId,
    label,
    address,
    ipv6Address,
    publicKey,
    createdAt,
  );
}
