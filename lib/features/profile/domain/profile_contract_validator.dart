import 'package:fav/core/utils/ipv6.dart';
import 'package:fav/core/utils/validators.dart';
import 'package:fav/features/profile/domain/client_profile.dart';
import 'package:fav/features/servers/domain/network_configuration_validator.dart';
import 'package:fav/features/servers/domain/wireguard_installation.dart';

/// Returns `null` when a parsed v2 profile agrees with persisted server facts.
String? profileV2Problem({
  required ClientProfile profile,
  required NetworkConfiguration network,
  String? expectedIpv4Address,
  String? expectedIpv6Address,
  String? expectedClientPublicKey,
  String? expectedServerPublicKey,
}) {
  final networkProblem = networkConfigurationV2Problem(network);
  if (networkProblem != null) return networkProblem;
  if (profile.version != 2 || profile.ipv6Address == null) {
    return 'profile is not a complete v2 profile';
  }
  if (expectedIpv4Address != null && profile.address != expectedIpv4Address) {
    return 'profile IPv4 address does not match the peer record';
  }
  if (expectedIpv6Address != null &&
      profile.ipv6Address != expectedIpv6Address) {
    return 'profile IPv6 address does not match the peer record';
  }
  if (expectedClientPublicKey != null &&
      profile.clientPublicKey != expectedClientPublicKey) {
    return 'profile public key does not match the peer record';
  }
  if (expectedServerPublicKey != null &&
      profile.serverPublicKey != expectedServerPublicKey) {
    return 'profile server key does not match the installation';
  }

  if (!profile.address.endsWith('/32') || !isValidCidrV4(profile.address)) {
    return 'profile IPv4 address is invalid';
  }
  final addressParts = profile.address
      .split('/')
      .first
      .split('.')
      .map(int.parse)
      .toList();
  final subnetParts = network.ipv4Subnet!
      .split('/')
      .first
      .split('.')
      .map(int.parse)
      .toList();
  final slot = addressParts[3];
  if (slot < 2 ||
      slot > 254 ||
      addressParts[0] != subnetParts[0] ||
      addressParts[1] != subnetParts[1] ||
      addressParts[2] != subnetParts[2]) {
    return 'profile IPv4 address is outside the installation subnet';
  }
  final expectedV6 = ipv6AddressForSlot(network.ipv6Subnet!, slot);
  if (profile.ipv6Address != '$expectedV6/128') {
    return 'profile IPv4 and IPv6 addresses use different slots';
  }
  return null;
}
