import 'dart:convert';

import 'package:fav/features/servers/data/network_mappers.dart';
import 'package:fav/features/servers/domain/network_configuration_validator.dart';
import 'package:fav/features/servers/domain/wireguard_installation.dart';

/// Strict parser for the authoritative v2 result produced by the installer.
class NetworkResultParser {
  /// Creates a parser.
  const NetworkResultParser();

  /// Parses and cross-checks a result against the request that created it.
  NetworkConfiguration parse(
    String source, {
    required String expectedInstallationId,
    required String expectedOperationId,
    required String expectedIpv4Subnet,
    required String expectedFallbackIpv6Subnet,
  }) {
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException {
      throw const FormatException('network result is not valid JSON');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('network result must be an object');
    }
    if (decoded['schemaVersion'] != 2) {
      throw const FormatException('network result version is unsupported');
    }
    if (decoded['installationId'] != expectedInstallationId ||
        decoded['operationId'] != expectedOperationId ||
        decoded['revision'] != 1) {
      throw const FormatException('network result identity mismatch');
    }
    final network = decoded['network'];
    final capability = decoded['capability'];
    if (network is! Map<String, dynamic> ||
        capability is! Map<String, dynamic>) {
      throw const FormatException('network result is incomplete');
    }
    final parsed = networkConfigurationFromMap({
      'schemaVersion': decoded['schemaVersion'],
      'installationId': decoded['installationId'],
      'revision': decoded['revision'],
      'ipv6Mode': network['ipv6Mode'],
      'ipv4Subnet': network['ipv4Subnet'],
      'ipv6Subnet': network['ipv6Subnet'],
      'fallbackIpv6Subnet': network['fallbackIpv6Subnet'],
      'serverIpv6Address': network['serverIpv6Address'],
      'capabilityStatus': capability['status'],
      'capabilityReason': capability['reason'],
      'capabilityCheckedAt': capability['checkedAt'],
    });
    if (parsed.ipv4Subnet != expectedIpv4Subnet ||
        parsed.fallbackIpv6Subnet != expectedFallbackIpv6Subnet) {
      throw const FormatException('network result request mismatch');
    }
    final problem = networkConfigurationV2Problem(parsed);
    if (problem != null) {
      throw FormatException('network result is invalid: $problem');
    }
    return parsed;
  }
}
