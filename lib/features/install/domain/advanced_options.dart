import 'package:fav/core/utils/equality.dart';
import 'package:meta/meta.dart';

/// Advanced WireGuard and provisioning options (spec §4.1, RF-17).
///
/// Every field defaults to the recommended value from the spec.
@immutable
class AdvancedOptions {
  /// Creates an [AdvancedOptions] with the spec default values.
  const AdvancedOptions({
    this.wgPort = 51820,
    this.vpnSubnet = '10.13.13.0/24',
    this.dns = '1.1.1.1, 1.0.0.1',
    this.mtu = 1420,
    this.interfaceName = 'wg0',
    this.publicEndpoint,
    this.delegatedIpv6Prefix,
    this.ipv6ProbeTarget,
    this.enableHardening = false,
    this.enableMonitoring = true,
    this.backupExistingConfig = true,
    this.userAuthorizedKeys = const [],
  });

  /// UDP port WireGuard listens on.
  final int wgPort;

  /// VPN subnet in CIDR notation.
  final String vpnSubnet;

  /// DNS servers advertised to clients, comma-separated.
  final String dns;

  /// Interface MTU.
  final int mtu;

  /// WireGuard interface name.
  final String interfaceName;

  /// Public endpoint override; `null` to use the detected public IP.
  final String? publicEndpoint;

  /// Optional provider-delegated IPv6 /64 supplied for routed mode.
  final String? delegatedIpv6Prefix;

  /// Optional operator-configured external IPv6 target used by the routed
  /// return-path probe. No target is contacted by default.
  final String? ipv6ProbeTarget;

  /// Whether to apply optional SSH hardening (fail2ban and key auth).
  final bool enableHardening;

  /// Whether to install the peer-monitoring agent on the server (M15-T7).
  /// Defaults to true; the install form exposes a toggle to skip it.
  final bool enableMonitoring;

  /// Whether to back up an existing configuration before overwriting it.
  final bool backupExistingConfig;

  /// User-supplied SSH public keys to deploy to the management account during
  /// the install run, so the user keeps their own access after hardening. Each
  /// entry is a normalized OpenSSH `authorized_keys` line (`SshPublicKey`).
  final List<String> userAuthorizedKeys;

  /// Returns a copy of these options with the given fields replaced.
  AdvancedOptions copyWith({
    int? wgPort,
    String? vpnSubnet,
    String? dns,
    int? mtu,
    String? interfaceName,
    String? publicEndpoint,
    String? delegatedIpv6Prefix,
    String? ipv6ProbeTarget,
    bool? enableHardening,
    bool? enableMonitoring,
    bool? backupExistingConfig,
    List<String>? userAuthorizedKeys,
  }) {
    return AdvancedOptions(
      wgPort: wgPort ?? this.wgPort,
      vpnSubnet: vpnSubnet ?? this.vpnSubnet,
      dns: dns ?? this.dns,
      mtu: mtu ?? this.mtu,
      interfaceName: interfaceName ?? this.interfaceName,
      publicEndpoint: publicEndpoint ?? this.publicEndpoint,
      delegatedIpv6Prefix: delegatedIpv6Prefix ?? this.delegatedIpv6Prefix,
      ipv6ProbeTarget: ipv6ProbeTarget ?? this.ipv6ProbeTarget,
      enableHardening: enableHardening ?? this.enableHardening,
      enableMonitoring: enableMonitoring ?? this.enableMonitoring,
      backupExistingConfig: backupExistingConfig ?? this.backupExistingConfig,
      userAuthorizedKeys: userAuthorizedKeys ?? this.userAuthorizedKeys,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is AdvancedOptions &&
        other.wgPort == wgPort &&
        other.vpnSubnet == vpnSubnet &&
        other.dns == dns &&
        other.mtu == mtu &&
        other.interfaceName == interfaceName &&
        other.publicEndpoint == publicEndpoint &&
        other.delegatedIpv6Prefix == delegatedIpv6Prefix &&
        other.ipv6ProbeTarget == ipv6ProbeTarget &&
        other.enableHardening == enableHardening &&
        other.enableMonitoring == enableMonitoring &&
        other.backupExistingConfig == backupExistingConfig &&
        listEquals(other.userAuthorizedKeys, userAuthorizedKeys);
  }

  @override
  int get hashCode {
    return Object.hash(
      wgPort,
      vpnSubnet,
      dns,
      mtu,
      interfaceName,
      publicEndpoint,
      delegatedIpv6Prefix,
      ipv6ProbeTarget,
      enableHardening,
      enableMonitoring,
      backupExistingConfig,
      Object.hashAll(userAuthorizedKeys),
    );
  }
}
