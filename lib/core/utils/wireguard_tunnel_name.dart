/// Builds the file name used when exporting a peer `.conf`.
///
/// The official WireGuard apps (Android and iOS) take the file name *without*
/// the `.conf` extension as the tunnel name, and reject anything that does not
/// match `[a-zA-Z0-9_=+.-]{1,15}` with an "Invalid name" error. A UUID-based
/// name (e.g. `wireguard-<uuid>`) is far longer than 15 characters and always
/// fails to import.
///
/// This helper derives a human-readable, WireGuard-valid name from the server
/// and (optional) peer labels: each label is sanitized to the allowed
/// character set and the two are joined with `-`, balanced-truncated so the
/// whole name fits within [_maxLength] characters. Returns [_fallback] when
/// nothing usable remains.
library;

const int _maxLength = 15;
const String _fallback = 'tunnel';

/// Characters WireGuard disallows in a tunnel name — everything outside
/// `[a-zA-Z0-9_=+.-]`.
final RegExp _disallowed = RegExp('[^a-zA-Z0-9_=+.-]+');

/// Leading/trailing separators we trim for a tidy name (still valid, just ugly).
final RegExp _edgeSeparators = RegExp(r'^[-_.+=]+|[-_.+=]+$');

/// Returns a WireGuard-valid file name (with the `.conf` extension) for the
/// peer belonging to [serverLabel], optionally qualified by [peerLabel].
String wireguardConfFileName({
  required String serverLabel,
  String? peerLabel,
}) => '${_buildName(serverLabel, peerLabel)}.conf';

String _buildName(String serverLabel, String? peerLabel) {
  final server = _sanitize(serverLabel);
  final peer = _sanitize(peerLabel ?? '');

  if (server.isEmpty && peer.isEmpty) {
    return _fallback;
  }
  if (peer.isEmpty) {
    return _trimEdges(_truncate(server, _maxLength));
  }
  if (server.isEmpty) {
    return _trimEdges(_truncate(peer, _maxLength));
  }

  // Both parts present: reserve one character for the `-` separator.
  const budget = _maxLength - 1;
  var serverLen = server.length;
  var peerLen = peer.length;
  if (serverLen + peerLen > budget) {
    const half = budget ~/ 2;
    if (serverLen <= half) {
      peerLen = budget - serverLen;
    } else if (peerLen <= budget - half) {
      serverLen = budget - peerLen;
    } else {
      serverLen = half;
      peerLen = budget - half;
    }
  }
  final name =
      '${server.substring(0, serverLen)}-${peer.substring(0, peerLen)}';
  final trimmed = _trimEdges(name);
  return trimmed.isEmpty ? _fallback : trimmed;
}

/// Maps whitespace to `-`, drops every other disallowed character, and
/// collapses repeated separators.
String _sanitize(String input) {
  final spacesToDash = input.trim().replaceAll(RegExp(r'\s+'), '-');
  final allowedOnly = spacesToDash.replaceAll(_disallowed, '');
  return allowedOnly.replaceAll(RegExp('-+'), '-');
}

String _truncate(String value, int max) =>
    value.length <= max ? value : value.substring(0, max);

String _trimEdges(String value) {
  final trimmed = value.replaceAll(_edgeSeparators, '');
  return trimmed.isEmpty ? _fallback : trimmed;
}
