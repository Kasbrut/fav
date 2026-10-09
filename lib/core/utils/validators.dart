// Pure input validators for the fields described in spec §9.2. Each function
// is side-effect free and returns whether the raw input is acceptable; the
// presentation layer maps a `false` result to a localized error message.

import 'package:fav/core/crypto/ssh_public_key.dart';
import 'package:fav/core/utils/ipv6.dart';

final RegExp _usernameRegex = RegExp(r'^[a-z_][a-z0-9_-]{0,31}$');

final RegExp _digitsOnlyRegex = RegExp(r'^[0-9]+$');

final RegExp _hostnameRegex = RegExp(
  r'^(?=.{1,253}$)[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?'
  r'(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$',
);

final List<RegExp> _passwordClassPatterns = [
  RegExp('[a-z]'),
  RegExp('[A-Z]'),
  RegExp('[0-9]'),
  RegExp('[^a-zA-Z0-9]'),
];

/// Whether [value] is an acceptable server label (1–50 characters).
bool isValidServerLabel(String value) {
  return value.isNotEmpty && value.length <= 50;
}

final RegExp _peerLabelRegex = RegExp(r'^[\p{L}\p{N} ._-]+$', unicode: true);

/// Whether [value] is an acceptable peer label for the multi-peer v1.1 flow:
/// 1–32 characters after trimming, drawn from Unicode letters and digits
/// plus space, dot, underscore and hyphen.
bool isValidPeerLabel(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty || trimmed.length > 32) {
    return false;
  }
  return _peerLabelRegex.hasMatch(trimmed);
}

/// Whether [value] is a valid dotted-decimal IPv4 address.
bool isValidIpv4(String value) {
  final octets = value.split('.');
  if (octets.length != 4) {
    return false;
  }
  for (final octet in octets) {
    if (!_digitsOnlyRegex.hasMatch(octet) || octet.length > 3) {
      return false;
    }
    final n = int.parse(octet);
    if (n > 255) {
      return false;
    }
  }
  return true;
}

/// Whether [value] is a valid IPv6 address.
///
/// Accepts the standard forms: full eight-group, `::` zero-compression (at
/// most once), and an embedded trailing IPv4 group (e.g. `::ffff:192.0.2.1`).
/// Surrounding brackets (`[::1]`) are tolerated; zone identifiers are not.
bool isValidIpv6(String value) {
  var v = value;
  if (v.length >= 2 && v.startsWith('[') && v.endsWith(']')) {
    v = v.substring(1, v.length - 1);
  }
  return parseIpv6(v) != null;
}

/// Whether [value] is a valid IPv4 address, IPv6 address, or RFC 1123
/// hostname. Used for the SSH target and the WireGuard public endpoint, both
/// of which may legitimately be an IP or a (possibly dynamic-DNS) domain.
bool isValidHostOrIp(String value) {
  return isValidIpv4(value) ||
      isValidIpv6(value) ||
      _hostnameRegex.hasMatch(value);
}

/// Whether [value] is a valid TCP/UDP port number (1–65535).
///
/// Used for both the SSH port and the WireGuard listen port.
bool isValidPort(String value) {
  final port = int.tryParse(value);
  return port != null && port >= 1 && port <= 65535;
}

/// Whether [value] is a valid SSH/Linux login username
/// (matches `^[a-z_][a-z0-9_-]{0,31}$`).
bool isValidLoginUsername(String value) {
  return _usernameRegex.hasMatch(value);
}

/// Whether [value] is a valid username for a new non-root user: the same rule
/// as [isValidLoginUsername], and never `root`.
bool isValidNewUsername(String value) {
  return isValidLoginUsername(value) && value != 'root';
}

/// Network interface name pattern: Linux caps interface names at 15 chars
/// (IFNAMSIZ is 16 including the trailing NUL), so the tail allows 0–14 more.
final RegExp _interfaceNameRegex = RegExp(r'^[a-z_][a-z0-9_-]{0,14}$');

/// Whether [value] is a valid WireGuard interface name. Stricter than
/// [isValidLoginUsername]: a 16+ char name would pass the username rule but
/// fail server-side at `wg-quick` (audit M8).
bool isValidInterfaceName(String value) {
  return _interfaceNameRegex.hasMatch(value);
}

/// Whether [value] is a non-empty login password.
///
/// The server enforces its own policy, so only emptiness is checked (§9.2).
bool isValidLoginPassword(String value) {
  return value.isNotEmpty;
}

/// Whether [value] satisfies the new-user password policy: at least 12
/// characters and at least 3 of the 4 character classes — lowercase,
/// uppercase, digit and symbol (spec §9.2, RF-06).
bool isValidNewPassword(String value) {
  if (value.length < 12 || RegExp(r'[\x00-\x1f\x7f]').hasMatch(value)) {
    return false;
  }
  final classes = _passwordClassPatterns.where((p) => p.hasMatch(value)).length;
  return classes >= 3;
}

/// Whether [password] and [confirmation] are identical.
bool passwordsMatch(String password, String confirmation) {
  return password == confirmation;
}

/// Whether [value] is a valid IPv4 CIDR block (for example `10.13.13.0/24`).
bool isValidCidrV4(String value) {
  final parts = value.split('/');
  if (parts.length != 2) {
    return false;
  }
  final prefix = int.tryParse(parts[1]);
  if (prefix == null || prefix < 0 || prefix > 32) {
    return false;
  }
  return isValidIpv4(parts[0]);
}

/// Whether [value] is an IPv6 CIDR (without brackets or zone identifiers).
bool isValidCidrV6(String value) {
  final parts = value.split('/');
  final prefix =
      parts.length == 2 &&
          parts[1].isNotEmpty &&
          parts[1].codeUnits.every((c) => c >= 48 && c <= 57)
      ? int.tryParse(parts[1])
      : null;
  return prefix != null &&
      prefix >= 0 &&
      prefix <= 128 &&
      parseIpv6(parts[0]) != null;
}

/// Whether [value] is a canonical tunnel /64 in ULA or GUA space.
bool isValidVpnSubnetV6(String value) {
  if (!isValidCidrV6(value) || !value.endsWith('/64')) return false;
  final address = value.substring(0, value.length - 3);
  final bytes = parseIpv6(address)!;
  if (bytes.sublist(8).any((b) => b != 0)) return false;
  final canonical = canonicalizeIpv6(address);
  if (canonical != address) return false;
  final ula = bytes[0] == 0xfd;
  final gua = bytes[0] >= 0x20 && bytes[0] <= 0x3f;
  final documentation =
      bytes[0] == 0x20 &&
      bytes[1] == 0x01 &&
      bytes[2] == 0x0d &&
      bytes[3] == 0xb8;
  return (ula || gua) && !documentation;
}

/// Whether [value] is a canonical IPv4 /24 network supported by the allocator.
/// The server uses .1 and peers use .2 through .254.
bool isValidVpnSubnet(String value) {
  if (!isValidCidrV4(value) || !value.endsWith('.0/24')) return false;
  return value
      .split('/')
      .first
      .split('.')
      .every(
        (octet) => octet == int.parse(octet).toString(),
      );
}

/// Whether [value] is a valid interface MTU (576–1500).
bool isValidMtu(String value) {
  final mtu = int.tryParse(value);
  return mtu != null && mtu >= 576 && mtu <= 1500;
}

/// Whether [value] is a full-tunnel MTU (1280–1500).
bool isValidFullTunnelMtu(String value) {
  final mtu = int.tryParse(value);
  return mtu != null && mtu >= 1280 && mtu <= 1500;
}

/// Whether [value] is a non-empty, comma-separated list of valid IPv4 or IPv6
/// addresses (for example `1.1.1.1, 1.0.0.1`).
bool isValidDnsList(String value) {
  final entries = value.split(',').map((e) => e.trim()).toList();
  if (entries.any((e) => e.isEmpty)) {
    return false;
  }
  return entries.every((e) => isValidIpv4(e) || (parseIpv6(e) != null));
}

/// Whether [value] is a single, well-formed OpenSSH public-key line of an
/// accepted type (delegates to [SshPublicKey.tryParse]).
bool isValidSshPublicKey(String value) {
  return SshPublicKey.tryParse(value) != null;
}
