import 'package:fav/core/utils/equality.dart';
import 'package:meta/meta.dart';

/// Effective IPv6 routing mode.
enum Ipv6Mode {
  /// Routed IPv6.
  routed,

  /// Blocked IPv6.
  blocked,

  /// Legacy mode.
  legacy,
}

/// IPv6 capability probe result.
enum CapabilityStatus {
  /// Capability is supported.
  supported,

  /// Capability is unavailable.
  unavailable,

  /// Capability is unknown.
  unknown,
}

/// Structural state of persisted network metadata.
enum NetworkMetadataStatus {
  /// Unversioned legacy metadata.
  legacy,

  /// Complete supported metadata.
  valid,

  /// Future unsupported version.
  unsupported,

  /// Malformed metadata.
  invalid,
}

/// Result of the post-install WireGuard UDP reachability check.
enum WireguardPortReachability {
  /// The marker reached the server from the device running FAV.
  reachable,

  /// The server did not receive the marker, usually because of a firewall.
  blocked,

  /// The check could not produce a reliable result.
  unknown,
}

/// Versioned effective network configuration persisted with an installation.
@immutable
class NetworkConfiguration {
  /// Creates network metadata.
  const NetworkConfiguration({
    this.schemaVersion,
    this.installationId,
    this.revision,
    this.ipv6Mode,
    this.ipv4Subnet,
    this.ipv6Subnet,
    this.fallbackIpv6Subnet,
    this.serverIpv6Address,
    this.capabilityStatus,
    this.capabilityReason,
    this.capabilityCheckedAt,
    this.status = NetworkMetadataStatus.legacy,
    this.rawMetadata,
  });

  /// Storage schema version.
  final int? schemaVersion;

  /// Stable installation identity.
  final String? installationId;

  /// Committed revision.
  final int? revision;

  /// Effective IPv6 mode.
  final Ipv6Mode? ipv6Mode;

  /// IPv4 subnet.
  final String? ipv4Subnet;

  /// Effective IPv6 subnet.
  final String? ipv6Subnet;

  /// Fallback ULA subnet.
  final String? fallbackIpv6Subnet;

  /// Server IPv6 address.
  final String? serverIpv6Address;

  /// Capability result.
  final CapabilityStatus? capabilityStatus;

  /// Capability reason.
  final String? capabilityReason;

  /// Capability check time.
  final DateTime? capabilityCheckedAt;

  /// Metadata structural status.
  final NetworkMetadataStatus status;

  /// Original map for invalid or unsupported records. It is retained so a
  /// normal server save cannot erase fields from a future or corrupt schema.
  final Map<Object?, Object?>? rawMetadata;

  /// Structural metadata check only; does not certify deployment safety.
  bool get isStructurallyValidV2 => status == NetworkMetadataStatus.valid;
  @override
  bool operator ==(Object other) =>
      other is NetworkConfiguration &&
      other.schemaVersion == schemaVersion &&
      other.installationId == installationId &&
      other.revision == revision &&
      other.ipv6Mode == ipv6Mode &&
      other.ipv4Subnet == ipv4Subnet &&
      other.ipv6Subnet == ipv6Subnet &&
      other.fallbackIpv6Subnet == fallbackIpv6Subnet &&
      other.serverIpv6Address == serverIpv6Address &&
      other.capabilityStatus == capabilityStatus &&
      other.capabilityReason == capabilityReason &&
      other.capabilityCheckedAt == capabilityCheckedAt &&
      other.status == status &&
      _deepEquals(other.rawMetadata, rawMetadata);
  @override
  int get hashCode => Object.hash(
    schemaVersion,
    installationId,
    revision,
    ipv6Mode,
    ipv4Subnet,
    ipv6Subnet,
    fallbackIpv6Subnet,
    serverIpv6Address,
    capabilityStatus,
    capabilityReason,
    capabilityCheckedAt,
    status,
    _deepHash(rawMetadata),
  );
}

/// Summary of a single WireGuard peer.
///
/// Minimal for the MVP; multi-peer management arrives in v1.1 (spec §13.1).
@immutable
class PeerSummary {
  /// Creates a [PeerSummary].
  const PeerSummary({
    required this.publicKey,
    required this.allowedIp,
    this.ipv6Address,
    this.label,
  });

  /// The peer public key.
  final String publicKey;

  /// The peer address inside the VPN subnet (for example `10.13.13.2/32`).
  final String allowedIp;

  /// Explicit IPv4 compatibility view.
  String get ipv4Address => allowedIp;

  /// Optional IPv6 address.
  final String? ipv6Address;

  /// Optional human-readable name for the peer.
  final String? label;

  /// Returns a copy of this peer with the given fields replaced.
  PeerSummary copyWith({
    String? publicKey,
    String? allowedIp,
    String? ipv6Address,
    bool clearIpv6Address = false,
    String? label,
  }) {
    return PeerSummary(
      publicKey: publicKey ?? this.publicKey,
      allowedIp: allowedIp ?? this.allowedIp,
      ipv6Address: clearIpv6Address ? null : (ipv6Address ?? this.ipv6Address),
      label: label ?? this.label,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is PeerSummary &&
        other.publicKey == publicKey &&
        other.allowedIp == allowedIp &&
        other.ipv6Address == ipv6Address &&
        other.label == label;
  }

  @override
  int get hashCode =>
      Object.hash(publicKey, allowedIp, ipv4Address, ipv6Address, label);
}

/// Details of a completed WireGuard installation on a server.
@immutable
class WireguardInstallation {
  /// Creates a [WireguardInstallation].
  const WireguardInstallation({
    required this.interfaceName,
    required this.listenPort,
    required this.vpnSubnet,
    required this.serverPublicKey,
    required this.peers,
    required this.hardeningApplied,
    required this.installedAt,
    this.rootSshDisabled = false,
    this.portReachability = WireguardPortReachability.unknown,
    this.portCheckedAt,
    this.publicEndpoint,
    this.network,
  });

  /// WireGuard interface name (for example `wg0`).
  final String interfaceName;

  /// UDP port the interface listens on.
  /// UDP port the interface listens on.
  final int listenPort;

  /// VPN subnet in CIDR notation (for example `10.13.13.0/24`).
  final String vpnSubnet;

  /// The server public key.
  final String serverPublicKey;

  /// Known peers configured on the interface.
  final List<PeerSummary> peers;

  /// Whether optional SSH hardening was applied.
  final bool hardeningApplied;

  /// Whether the anti-lockout sequence disabled root SSH login.
  ///
  /// Tracked separately from [hardeningApplied]: anti-lockout runs on every
  /// root-login install, hardening is opt-in. The teardown modal offers the
  /// re-open-SSH revert when either changed the server's SSH access.
  final bool rootSshDisabled;

  /// When the installation completed.
  final DateTime installedAt;

  /// Result of checking the selected UDP port from outside the server.
  final WireguardPortReachability portReachability;

  /// When [portReachability] was last conclusively checked.
  final DateTime? portCheckedAt;

  /// Public host used by WireGuard clients, retained for diagnostics.
  final String? publicEndpoint;

  /// Versioned effective network configuration.
  final NetworkConfiguration? network;

  /// Returns a copy of this installation with the given fields replaced.
  WireguardInstallation copyWith({
    String? interfaceName,
    int? listenPort,
    String? vpnSubnet,
    String? serverPublicKey,
    List<PeerSummary>? peers,
    bool? hardeningApplied,
    bool? rootSshDisabled,
    DateTime? installedAt,
    WireguardPortReachability? portReachability,
    DateTime? portCheckedAt,
    String? publicEndpoint,
    NetworkConfiguration? network,
    bool clearNetwork = false,
  }) {
    return WireguardInstallation(
      interfaceName: interfaceName ?? this.interfaceName,
      listenPort: listenPort ?? this.listenPort,
      vpnSubnet: vpnSubnet ?? this.vpnSubnet,
      serverPublicKey: serverPublicKey ?? this.serverPublicKey,
      peers: peers ?? this.peers,
      hardeningApplied: hardeningApplied ?? this.hardeningApplied,
      rootSshDisabled: rootSshDisabled ?? this.rootSshDisabled,
      installedAt: installedAt ?? this.installedAt,
      portReachability: portReachability ?? this.portReachability,
      portCheckedAt: portCheckedAt ?? this.portCheckedAt,
      publicEndpoint: publicEndpoint ?? this.publicEndpoint,
      network: clearNetwork ? null : (network ?? this.network),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is WireguardInstallation &&
        other.interfaceName == interfaceName &&
        other.listenPort == listenPort &&
        other.vpnSubnet == vpnSubnet &&
        other.serverPublicKey == serverPublicKey &&
        listEquals(other.peers, peers) &&
        other.hardeningApplied == hardeningApplied &&
        other.rootSshDisabled == rootSshDisabled &&
        other.installedAt == installedAt &&
        other.portReachability == portReachability &&
        other.portCheckedAt == portCheckedAt &&
        other.publicEndpoint == publicEndpoint &&
        other.network == network;
  }

  @override
  int get hashCode {
    return Object.hash(
      interfaceName,
      listenPort,
      vpnSubnet,
      serverPublicKey,
      Object.hashAll(peers),
      hardeningApplied,
      rootSshDisabled,
      installedAt,
      portReachability,
      portCheckedAt,
      publicEndpoint,
      network,
    );
  }
}

bool _deepEquals(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (!b.containsKey(entry.key) ||
          !_deepEquals(entry.value, b[entry.key])) {
        return false;
      }
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_deepEquals(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}

int _deepHash(Object? value) {
  if (value is Map) {
    return Object.hashAllUnordered(
      value.entries.map(
        (entry) => Object.hash(entry.key, _deepHash(entry.value)),
      ),
    );
  }
  if (value is List) return Object.hashAll(value.map(_deepHash));
  return value.hashCode;
}
