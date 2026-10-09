import 'dart:math';

/// Parses an IPv6 literal into its 16 network-order bytes.
///
/// Brackets and zone identifiers are deliberately not accepted here because
/// this helper is also used for CIDR fields. The endpoint validator retains
/// bracket-friendly behaviour.
List<int>? parseIpv6(String value) {
  if (value.isEmpty ||
      value.contains('%') ||
      value.codeUnits.any((c) => c <= 32 || c == 127)) {
    return null;
  }
  final input = value;
  if (input.startsWith('[') || input.endsWith(']')) return null;
  if (!input.contains(':')) return null;

  final compression = input.indexOf('::');
  if (compression != input.lastIndexOf('::')) return null;
  final hasCompression = compression >= 0;
  final parts = hasCompression
      ? <String>[
          input.substring(0, compression),
          input.substring(compression + 2),
        ]
      : <String>[input];
  // A dotted-quad is the final 32 bits, so it cannot occur on the left of
  // zero compression (nor be followed by another token).
  if (hasCompression && parts[0].contains('.')) return null;
  List<String> split(String s) => s.isEmpty ? <String>[] : s.split(':');
  final tokens = <String>[
    ...split(parts[0]),
    if (hasCompression) ...split(parts[1]),
  ];
  var groups = 0;
  final values = <int>[];
  for (var i = 0; i < tokens.length; i++) {
    final token = tokens[i];
    final last = i == tokens.length - 1;
    if (token.contains('.')) {
      if (!last) return null;
      final octets = token.split('.');
      if (octets.length != 4) return null;
      for (final octet in octets) {
        if (octet.isEmpty || !RegExp(r'^(?:0|[1-9]\d{0,2})$').hasMatch(octet)) {
          return null;
        }
        final n = int.parse(octet);
        if (n > 255) return null;
        values.add(n);
      }
      groups += 2;
    } else {
      if (!RegExp(r'^[0-9a-fA-F]{1,4}$').hasMatch(token)) return null;
      values.addAll([
        int.parse(token, radix: 16) >> 8,
        int.parse(token, radix: 16) & 255,
      ]);
      groups++;
    }
  }
  if (hasCompression ? groups >= 8 : groups != 8) return null;
  if (hasCompression) {
    final zeros = List<int>.filled(16 - values.length, 0);
    // The left side cannot contain an IPv4 tail (rejected above).
    final leftBytes = split(parts[0]).length * 2;
    return [...values.take(leftBytes), ...zeros, ...values.skip(leftBytes)];
  }
  return values;
}

/// Formats 16 IPv6 bytes according to RFC 5952-style canonical rules.
String formatIpv6(List<int> bytes) {
  if (bytes.length != 16 || bytes.any((b) => b < 0 || b > 255)) {
    throw ArgumentError('IPv6 requires 16 bytes');
  }
  final groups = List<int>.generate(
    8,
    (i) => (bytes[i * 2] << 8) | bytes[i * 2 + 1],
  );
  if (groups.every((group) => group == 0)) return '::';
  var bestStart = -1;
  var bestLength = 1;
  var i = 0;
  while (i < 8) {
    if (groups[i] == 0) {
      var j = i;
      while (j < 8 && groups[j] == 0) {
        j++;
      }
      if (j - i > bestLength) {
        bestStart = i;
        bestLength = j - i;
      }
      i = j;
    } else {
      i++;
    }
  }
  final out = <String>[];
  i = 0;
  while (i < 8) {
    if (i == bestStart) {
      out.add('');
      i += bestLength;
      if (bestStart == 0 || i == 8) out.add('');
    } else {
      out.add(groups[i].toRadixString(16));
      i++;
    }
  }
  return out.join(':');
}

/// Returns the canonical textual form of an IPv6 literal, or `null` if invalid.
String? canonicalizeIpv6(String value) {
  final bytes = parseIpv6(value);
  return bytes == null ? null : formatIpv6(bytes);
}

/// Returns whether [address] falls inside [prefix]/[prefixLength].
bool ipv6InPrefix(String address, String prefix, int prefixLength) {
  final a = parseIpv6(address);
  final p = parseIpv6(prefix);
  if (a == null || p == null || prefixLength < 0 || prefixLength > 128) {
    return false;
  }
  final whole = prefixLength ~/ 8;
  final bits = prefixLength % 8;
  for (var i = 0; i < whole; i++) {
    if (a[i] != p[i]) return false;
  }
  return bits == 0 || (a[whole] >> (8 - bits)) == (p[whole] >> (8 - bits));
}

/// Returns whether an IPv6 address falls inside an IPv6 CIDR string.
bool isIpv6InPrefix(String address, String cidr) {
  final parts = cidr.split('/');
  final n =
      parts.length == 2 &&
          parts[1].isNotEmpty &&
          parts[1].codeUnits.every((c) => c >= 48 && c <= 57)
      ? int.tryParse(parts[1])
      : null;
  return n != null && ipv6InPrefix(address, parts[0], n);
}

/// Returns a canonical address for [slot] (1–254) in an IPv6 /64 network.
///
/// [prefix] may be a bare network address or include `/64`; host bits must
/// be zero. This performs address arithmetic, not tunnel eligibility checks.
String? ipv6AddressForSlot(String prefix, int slot) {
  final cidr = prefix.split('/');
  if (cidr.length > 2 || (cidr.length == 2 && cidr[1] != '64')) return null;
  final bytes = parseIpv6(cidr[0]);
  if (bytes == null ||
      slot < 1 ||
      slot > 254 ||
      bytes.sublist(8).any((b) => b != 0)) {
    return null;
  }
  // All host bytes are zero and the largest slot fits in one byte.
  bytes[15] = slot;
  return formatIpv6(bytes);
}

/// Generates a ULA /64: fd + 40 random global-ID bits + zero subnet ID.
String generateUlaSubnet({Random? random, List<int>? randomBytes}) {
  if (randomBytes != null &&
      (randomBytes.length != 5 || randomBytes.any((b) => b < 0 || b > 255))) {
    throw ArgumentError('five random bytes required');
  }
  final List<int> id;
  if (randomBytes != null) {
    id = randomBytes;
  } else {
    final source = random ?? Random.secure();
    id = List<int>.generate(5, (_) => source.nextInt(256));
  }
  return '${formatIpv6([0xfd, ...id, ...List<int>.filled(10, 0)])}/64';
}
