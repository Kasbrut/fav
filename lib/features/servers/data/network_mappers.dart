import 'package:fav/features/servers/domain/wireguard_installation.dart';

/// Serializes network metadata without converting corrupt records to legacy.
Map<Object?, Object?> networkConfigurationToMap(NetworkConfiguration n) =>
    n.status != NetworkMetadataStatus.legacy &&
        n.status != NetworkMetadataStatus.valid &&
        n.rawMetadata != null
    ? Map<Object?, Object?>.from(n.rawMetadata!)
    : {
        if (n.schemaVersion != null || n.status != NetworkMetadataStatus.legacy)
          'schemaVersion': n.schemaVersion,
        'installationId': n.installationId,
        'revision': n.revision,
        'ipv6Mode': n.ipv6Mode?.name,
        'ipv4Subnet': n.ipv4Subnet,
        'ipv6Subnet': n.ipv6Subnet,
        'fallbackIpv6Subnet': n.fallbackIpv6Subnet,
        'serverIpv6Address': n.serverIpv6Address,
        'capabilityStatus': n.capabilityStatus?.name,
        'capabilityReason': n.capabilityReason,
        'capabilityCheckedAt': n.capabilityCheckedAt?.toIso8601String(),
      };

/// Reads persisted metadata; structural validity does not certify connectivity.
NetworkConfiguration networkConfigurationFromMap(Object? raw) {
  if (raw is! Map) {
    return const NetworkConfiguration(status: NetworkMetadataStatus.invalid);
  }
  final m = raw;
  final rawVersion = m['schemaVersion'];
  final version = rawVersion is int ? rawVersion : null;
  final mode = _enumByName(Ipv6Mode.values, m['ipv6Mode']);
  final capability = _enumByName(
    CapabilityStatus.values,
    m['capabilityStatus'],
  );
  final valid =
      version == 2 &&
      _nonEmpty(m['installationId']) &&
      m['revision'] is int &&
      (m['revision'] as int) > 0 &&
      mode != null &&
      mode != Ipv6Mode.legacy &&
      _nonEmpty(m['ipv4Subnet']) &&
      _nonEmpty(m['ipv6Subnet']) &&
      _nonEmpty(m['fallbackIpv6Subnet']) &&
      _nonEmpty(m['serverIpv6Address']) &&
      capability != null &&
      _nonEmpty(m['capabilityReason']) &&
      _safeDate(m['capabilityCheckedAt']) != null;
  final status = version == null
      ? (m.containsKey('schemaVersion')
            ? NetworkMetadataStatus.invalid
            : NetworkMetadataStatus.legacy)
      : version != 2
      ? NetworkMetadataStatus.unsupported
      : valid
      ? NetworkMetadataStatus.valid
      : NetworkMetadataStatus.invalid;
  return NetworkConfiguration(
    schemaVersion: version,
    installationId: _string(m['installationId']),
    revision: m['revision'] is int ? m['revision'] as int : null,
    ipv6Mode: mode,
    ipv4Subnet: _string(m['ipv4Subnet']),
    ipv6Subnet: _string(m['ipv6Subnet']),
    fallbackIpv6Subnet: _string(m['fallbackIpv6Subnet']),
    serverIpv6Address: _string(m['serverIpv6Address']),
    capabilityStatus: capability,
    capabilityReason: _string(m['capabilityReason']),
    capabilityCheckedAt: _safeDate(m['capabilityCheckedAt']),
    status: status,
    rawMetadata:
        status == NetworkMetadataStatus.invalid ||
            status == NetworkMetadataStatus.unsupported
        ? Map<Object?, Object?>.from(m)
        : null,
  );
}

bool _nonEmpty(Object? value) => value is String && value.trim().isNotEmpty;

String? _string(Object? value) => value is String ? value : null;
DateTime? _safeDate(Object? value) {
  if (value is! String) return null;
  try {
    return DateTime.parse(value);
  } on FormatException {
    return null;
  }
}

T? _enumByName<T extends Enum>(List<T> values, Object? raw) {
  if (raw is! String) return null;
  for (final value in values) {
    if (value.name == raw) return value;
  }
  return null;
}
