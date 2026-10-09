import 'package:fav/features/peers/domain/peer.dart';
import 'package:fav/features/servers/domain/wireguard_installation.dart';
import 'package:meta/meta.dart';

/// The result of a successful `peer_add.sh` run, parsed from the
/// sentinel-delimited stdout envelope:
///
///     ADDR=10.13.13.3/32
///     PUBKEY=<client public key>
///     ---BEGIN-CONF---
///     <client.conf body>
///     ---END-CONF---
///
/// The body between the sentinels is preserved verbatim and persisted in
/// secure storage; the address and public key feed the new [Peer] row.
@immutable
class PeerAddEnvelope {
  /// Creates a [PeerAddEnvelope].
  const PeerAddEnvelope({
    required this.address,
    required this.publicKey,
    required this.rawConf,
    this.ipv6Address,
    this.version = 1,
    this.installationId,
    this.operationId,
    this.revision,
    this.ipv6Mode,
  });

  /// Tunnel address with CIDR mask, e.g. `10.13.13.3/32`.
  final String address;

  /// Explicit IPv4 compatibility view.
  String get ipv4Address => address;

  /// Optional IPv6 address.
  final String? ipv6Address;

  /// The new peer's public key (server-side generated).
  final String publicKey;

  /// Raw `.conf` body the app stores in secure storage.
  final String rawConf;

  /// Envelope contract version; legacy output is version 1.
  final int version;

  /// V2 server installation identity.
  final String? installationId;

  /// V2 idempotent peer operation identity.
  final String? operationId;

  /// V2 manifest revision after the committed peer operation.
  final int? revision;

  /// V2 effective IPv6 mode reported by the server.
  final Ipv6Mode? ipv6Mode;

  @override
  bool operator ==(Object other) {
    return other is PeerAddEnvelope &&
        other.address == address &&
        other.ipv6Address == ipv6Address &&
        other.publicKey == publicKey &&
        other.rawConf == rawConf &&
        other.version == version &&
        other.installationId == installationId &&
        other.operationId == operationId &&
        other.revision == revision &&
        other.ipv6Mode == ipv6Mode;
  }

  @override
  int get hashCode => Object.hash(
    address,
    ipv4Address,
    ipv6Address,
    publicKey,
    rawConf,
    version,
    installationId,
    operationId,
    revision,
    ipv6Mode,
  );
}
