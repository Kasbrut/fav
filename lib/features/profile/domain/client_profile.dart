import 'package:meta/meta.dart';

/// A WireGuard client profile parsed from the `.conf` produced by the
/// installer's `99_finalize.sh` module (spec §8.2, RF-16).
///
/// Holds the values we surface in the UI (endpoint, address, DNS, …); the
/// authoritative copy is the raw `.conf` text persisted in secure storage —
/// this object is reconstructed from it on demand.
@immutable
class ClientProfile {
  /// Creates a [ClientProfile].
  const ClientProfile({
    required this.privateKey,
    required this.clientPublicKey,
    required this.address,
    required this.dns,
    required this.mtu,
    required this.serverPublicKey,
    required this.endpoint,
    required this.allowedIps,
    this.ipv6Address,
    this.presharedKey,
    this.persistentKeepalive,
    this.version = 1,
  });

  /// Client private key (X25519, base64). NEVER show to the user.
  final String privateKey;

  /// Client public key (X25519, standard base64, 44 chars). Derived from
  /// [privateKey] by the profile parser. Used to match the peer reported by
  /// `wg show wg0 dump` (M15-T3).
  final String clientPublicKey;

  /// Tunnel address with CIDR mask, e.g. `10.13.13.2/32`.
  final String address;

  /// Explicit IPv4 compatibility view.
  String get ipv4Address => address;

  /// Optional IPv6 address.
  final String? ipv6Address;

  /// DNS servers pushed to the client, in declaration order.
  final List<String> dns;

  /// Tunnel MTU.
  final int mtu;

  /// Server public key (X25519, base64).
  final String serverPublicKey;

  /// Optional preshared key (post-quantum mitigation, spec §10.1).
  final String? presharedKey;

  /// Server endpoint in `host:port` form.
  final String endpoint;

  /// Routes advertised to the client, e.g. `[0.0.0.0/0]` (full tunnel).
  final List<String> allowedIps;

  /// Optional keep-alive interval in seconds (for NAT traversal).
  final int? persistentKeepalive;

  /// Parsed profile contract version. Legacy profiles are version 1.
  final int version;

  @override
  bool operator ==(Object other) {
    return other is ClientProfile &&
        other.privateKey == privateKey &&
        other.clientPublicKey == clientPublicKey &&
        other.address == address &&
        other.ipv6Address == ipv6Address &&
        _listEquals(other.dns, dns) &&
        other.mtu == mtu &&
        other.serverPublicKey == serverPublicKey &&
        other.presharedKey == presharedKey &&
        other.endpoint == endpoint &&
        _listEquals(other.allowedIps, allowedIps) &&
        other.persistentKeepalive == persistentKeepalive &&
        other.version == version;
  }

  @override
  int get hashCode => Object.hash(
    privateKey,
    clientPublicKey,
    address,
    ipv6Address,
    Object.hashAll(dns),
    mtu,
    serverPublicKey,
    presharedKey,
    endpoint,
    Object.hashAll(allowedIps),
    persistentKeepalive,
    version,
  );
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
