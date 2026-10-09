import 'package:fav/core/utils/ipv6.dart';
import 'package:fav/core/utils/validators.dart';
import 'package:fav/features/servers/domain/wireguard_installation.dart';

/// Returns `null` when [network] is semantically usable as v2 metadata.
///
/// Structural parsing is deliberately insufficient here: managed operations
/// and profile export must also prove address, mode and evidence consistency.
String? networkConfigurationV2Problem(NetworkConfiguration? network) {
  if (network == null) return 'network metadata is missing';
  if (!network.isStructurallyValidV2) {
    return 'network metadata is ${network.status.name}';
  }
  final ipv4Subnet = network.ipv4Subnet!;
  final ipv6Subnet = network.ipv6Subnet!;
  final fallback = network.fallbackIpv6Subnet!;
  final serverAddress = network.serverIpv6Address!;
  final checkedAt = network.capabilityCheckedAt!;

  if (!_isSafeToken(network.installationId!) ||
      !_isSafeToken(network.capabilityReason!)) {
    return 'installation identity or capability reason is invalid';
  }
  if (!isValidVpnSubnet(ipv4Subnet)) return 'IPv4 subnet is not canonical /24';
  if (!isValidVpnSubnetV6(ipv6Subnet)) {
    return 'IPv6 subnet is not an eligible canonical /64';
  }
  if (!isValidVpnSubnetV6(fallback) || !_isUla(fallback)) {
    return 'fallback IPv6 subnet is not a canonical ULA /64';
  }
  if (!_isCanonicalHostCidr(serverAddress, 64) ||
      !isIpv6InPrefix(_host(serverAddress), ipv6Subnet)) {
    return 'server IPv6 address is outside the effective subnet';
  }
  final expectedServer = ipv6AddressForSlot(ipv6Subnet, 1);
  if (_host(serverAddress) != expectedServer) {
    return 'server IPv6 address is not slot 1';
  }
  if (!checkedAt.isUtc) return 'capability evidence time is not UTC';

  switch (network.ipv6Mode!) {
    case Ipv6Mode.routed:
      if (_isUla(ipv6Subnet)) {
        return 'routed mode requires a global IPv6 subnet';
      }
      if (network.capabilityStatus != CapabilityStatus.supported) {
        return 'routed mode requires supported capability evidence';
      }
    case Ipv6Mode.blocked:
      if (ipv6Subnet != fallback || !_isUla(ipv6Subnet)) {
        return 'blocked mode must use the fallback ULA subnet';
      }
      if (network.capabilityStatus == CapabilityStatus.supported) {
        return 'blocked mode conflicts with supported capability evidence';
      }
    case Ipv6Mode.legacy:
      return 'legacy is not a v2 IPv6 mode';
  }
  return null;
}

/// Whether [network] passed the complete local v2 semantic checks.
bool isSemanticallyValidNetworkV2(NetworkConfiguration? network) =>
    networkConfigurationV2Problem(network) == null;

bool _isUla(String cidr) => parseIpv6(cidr.split('/').first)![0] == 0xfd;

String _host(String cidr) => cidr.split('/').first;

bool _isCanonicalHostCidr(String value, int prefix) {
  final parts = value.split('/');
  return parts.length == 2 &&
      parts[1] == '$prefix' &&
      canonicalizeIpv6(parts[0]) == parts[0];
}

bool _isSafeToken(String value) =>
    RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$').hasMatch(value);
