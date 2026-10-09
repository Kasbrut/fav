import 'package:fav/core/errors/app_exception.dart';
import 'package:fav/core/utils/ipv6.dart';
import 'package:fav/core/utils/validators.dart';
import 'package:fav/core/wireguard/wg_public_key.dart';
import 'package:fav/features/profile/domain/client_profile.dart';
import 'package:fav/features/servers/domain/wireguard_installation.dart';

/// Parses a wg-quick client profile. Legacy profiles remain readable, while
/// callers that know they are handling v2 can request the stricter contract.
class ClientProfileParser {
  /// Creates a [ClientProfileParser].
  const ClientProfileParser();

  /// Parses [content]. [requireV2] validates the complete dual-stack profile
  /// emitted inside a peer envelope v2 or exported for a v2 installation.
  Future<ClientProfile> parse(
    String content, {
    bool requireV2 = false,
    Ipv6Mode? ipv6Mode,
  }) async {
    String? section;
    final iface = <String, List<String>>{};
    final peer = <String, List<String>>{};
    for (final raw in content.split('\n')) {
      final line = raw.replaceAll(RegExp('#.*'), '').trim();
      if (line.isEmpty) continue;
      if (line.startsWith('[') && line.endsWith(']')) {
        section = line.substring(1, line.length - 1).toLowerCase().trim();
        continue;
      }
      final eq = line.indexOf('=');
      if (eq <= 0) {
        if (requireV2) _invalid('client profile contains malformed data');
        continue;
      }
      final key = line.substring(0, eq).trim().toLowerCase();
      final value = line.substring(eq + 1).trim();
      switch (section) {
        case 'interface':
          iface.putIfAbsent(key, () => []).add(value);
        case 'peer':
          peer.putIfAbsent(key, () => []).add(value);
        default:
          if (requireV2) {
            _invalid('client profile contains data outside a known section');
          }
      }
    }
    if (requireV2) {
      for (final entries in [...iface.entries, ...peer.entries]) {
        if (entries.key != 'address' && entries.value.length != 1) {
          _invalid('client profile has duplicate ${entries.key} entries');
        }
      }
    }

    String required(
      Map<String, List<String>> source,
      String key,
      String label,
    ) {
      final values = source[key];
      if (requireV2 && values != null && values.length != 1) {
        _invalid('client profile has duplicate $label entries');
      }
      final value = values?.last;
      if (value == null || value.isEmpty) {
        _invalid('client profile is missing $label');
      }
      return value;
    }

    final addresses = (iface['address'] ?? const <String>[])
        .expand(_splitList)
        .toList();
    final ipv4Addresses = addresses.where(_isIpv4HostCidr).toList();
    final ipv6Addresses = addresses.where(_isIpv6HostCidr).toList();
    if (addresses.isEmpty ||
        ipv4Addresses.length != 1 ||
        ipv6Addresses.length > 1 ||
        ipv4Addresses.length + ipv6Addresses.length != addresses.length) {
      _invalid('client profile has invalid or conflicting Address entries');
    }
    if (requireV2 && (ipv6Mode == null || ipv6Addresses.length != 1)) {
      _invalid('v2 client profile requires one IPv4 and one IPv6 address');
    }

    final dns = _splitList(iface['dns']?.last ?? '');
    final allowedIps = _splitList(peer['allowedips']?.last ?? '');
    final mtuRaw = iface['mtu']?.last ?? '';
    final mtu = int.tryParse(mtuRaw);
    final keepAlive = int.tryParse(peer['persistentkeepalive']?.last ?? '');
    if (mtu == null) _invalid('client profile is missing MTU');

    final privateKey = required(iface, 'privatekey', 'PrivateKey');
    final WgPublicKey clientPublicKey;
    try {
      clientPublicKey = await WgPublicKey.fromPrivateKey(privateKey);
    } on FormatException catch (error) {
      throw AppException(
        ErrorCode.scriptInvalid,
        detail: 'client profile private key is invalid: ${error.message}',
      );
    }

    final serverPublicKey = required(peer, 'publickey', 'PublicKey');
    final presharedKey = peer['presharedkey']?.last;
    if (requireV2) {
      _validateV2(
        dns: dns,
        mtuRaw: mtuRaw,
        serverPublicKey: serverPublicKey,
        presharedKey: presharedKey,
        allowedIps: allowedIps,
        ipv6Mode: ipv6Mode!,
      );
    }

    return ClientProfile(
      privateKey: privateKey,
      clientPublicKey: clientPublicKey.canonical,
      address: ipv4Addresses.single,
      ipv6Address: ipv6Addresses.isEmpty ? null : ipv6Addresses.single,
      dns: dns,
      mtu: mtu,
      serverPublicKey: serverPublicKey,
      presharedKey: presharedKey,
      endpoint: required(peer, 'endpoint', 'Endpoint'),
      allowedIps: allowedIps,
      persistentKeepalive: keepAlive,
      version: requireV2 ? 2 : 1,
    );
  }
}

Never _invalid(String detail) =>
    throw AppException(ErrorCode.scriptInvalid, detail: detail);

bool _isIpv4HostCidr(String value) {
  if (!value.endsWith('/32') || !isValidCidrV4(value)) return false;
  return value
      .split('/')
      .first
      .split('.')
      .every((octet) => octet == int.parse(octet).toString());
}

bool _isIpv6HostCidr(String value) {
  final parts = value.split('/');
  return parts.length == 2 &&
      parts[1] == '128' &&
      canonicalizeIpv6(parts[0]) == parts[0];
}

void _validateV2({
  required List<String> dns,
  required String mtuRaw,
  required String serverPublicKey,
  required String? presharedKey,
  required List<String> allowedIps,
  required Ipv6Mode ipv6Mode,
}) {
  try {
    WgPublicKey.parse(serverPublicKey);
    if (presharedKey != null) WgPublicKey.parse(presharedKey);
  } on FormatException {
    _invalid('v2 client profile contains an invalid WireGuard key');
  }
  if (!isValidFullTunnelMtu(mtuRaw)) {
    _invalid('v2 client profile has an invalid MTU');
  }
  if (dns.isEmpty || !isValidDnsList(dns.join(','))) {
    _invalid('v2 client profile has invalid DNS addresses');
  }
  if (dns.any(_isUnusableDns)) {
    _invalid('v2 client profile has an unspecified or multicast DNS address');
  }
  if (ipv6Mode == Ipv6Mode.blocked && !dns.any(isValidIpv4)) {
    _invalid('blocked v2 profile requires an IPv4 DNS resolver');
  }
  if (allowedIps.length != 2 ||
      allowedIps.toSet().length != 2 ||
      !allowedIps.contains('0.0.0.0/0') ||
      !allowedIps.contains('::/0')) {
    _invalid('v2 client profile must contain both default routes');
  }
}

bool _isUnusableDns(String value) {
  if (isValidIpv4(value)) {
    final first = int.parse(value.split('.').first);
    return value == '0.0.0.0' || (first >= 224 && first <= 239);
  }
  final bytes = parseIpv6(value)!;
  return bytes.every((byte) => byte == 0) || bytes[0] == 0xff;
}

List<String> _splitList(String value) {
  if (value.isEmpty) return const [];
  return value
      .split(',')
      .map((entry) => entry.trim())
      .where((entry) => entry.isNotEmpty)
      .toList();
}
