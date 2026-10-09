import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:meta/meta.dart';

/// A user-supplied SSH public key in OpenSSH `authorized_keys` form
/// (`<type> <base64-blob> [comment]`).
///
/// Parsed from text the user pastes or imports from a `.pub` file so advanced
/// users keep their own interactive SSH access after the optional hardening
/// disables password login. Only public material is represented here — there
/// is no private key and nothing secret to redact.
///
/// Use [SshPublicKey.tryParse] for input validation: it returns `null` for
/// anything that is not a single, well-formed line of one of the accepted key
/// [types].
@immutable
class SshPublicKey {
  const SshPublicKey._({
    required this.algorithm,
    required this.comment,
    required this.line,
    required this.fingerprint,
  });

  /// Key types accepted from users, mapped by their OpenSSH name. The same
  /// string is also the algorithm name embedded in the wire-format blob, which
  /// [tryParse] cross-checks.
  static const Set<String> types = {
    'ssh-ed25519',
    'ssh-rsa',
    'ecdsa-sha2-nistp256',
    'ecdsa-sha2-nistp384',
    'ecdsa-sha2-nistp521',
    'sk-ssh-ed25519@openssh.com',
    'sk-ecdsa-sha2-nistp256@openssh.com',
  };

  /// The key type, e.g. `ssh-ed25519` (one of [types]).
  final String algorithm;

  /// The trailing comment, or `''` when the line has none.
  final String comment;

  /// The normalized single-line `authorized_keys` entry (`type base64
  /// [comment]`, single spaces, no surrounding whitespace). This is the value
  /// persisted and deployed to the server.
  final String line;

  /// The OpenSSH SHA-256 fingerprint (`SHA256:<base64-no-padding>`), shown to
  /// the user to identify the key.
  final String fingerprint;

  /// Parses [raw] into an [SshPublicKey], or returns `null` when it is not a
  /// single valid OpenSSH public-key line of an accepted [types].
  ///
  /// Rejects multi-line input and any control character so the result is safe
  /// to write into `config.env` and a server's `authorized_keys`.
  static SshPublicKey? tryParse(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    // Reject control characters (including embedded newlines): the value must
    // be a single, shell- and authorized_keys-safe line.
    if (RegExp(r'[\x00-\x1f]').hasMatch(trimmed)) {
      return null;
    }

    // type, base64 blob, then an optional free-form comment.
    final parts = trimmed.split(RegExp(r'[ \t]+'));
    if (parts.length < 2) {
      return null;
    }
    final type = parts[0];
    if (!types.contains(type)) {
      return null;
    }
    final blob = parts[1];
    final comment = parts.length > 2 ? parts.sublist(2).join(' ') : '';

    final List<int> bytes;
    try {
      bytes = base64.decode(blob);
    } on FormatException {
      return null;
    }
    // The blob must open with a uint32-length-prefixed string naming the same
    // algorithm as the type field — the strong check that this is a real key
    // of the claimed type and not arbitrary base64.
    if (_readWireString(bytes) != type) {
      return null;
    }

    final digest = sha256.convert(bytes).bytes;
    final fingerprint = 'SHA256:${base64.encode(digest).replaceAll('=', '')}';
    final normalized = comment.isEmpty ? '$type $blob' : '$type $blob $comment';
    return SshPublicKey._(
      algorithm: type,
      comment: comment,
      line: normalized,
      fingerprint: fingerprint,
    );
  }

  /// Reads the leading SSH wire-format string (`uint32 length || bytes`) from
  /// [bytes], or `null` when [bytes] is too short to contain one.
  static String? _readWireString(List<int> bytes) {
    if (bytes.length < 4) {
      return null;
    }
    final length =
        (bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3];
    if (4 + length > bytes.length) {
      return null;
    }
    return utf8.decode(bytes.sublist(4, 4 + length), allowMalformed: true);
  }

  @override
  bool operator ==(Object other) => other is SshPublicKey && other.line == line;

  @override
  int get hashCode => line.hashCode;

  @override
  String toString() => 'SshPublicKey($algorithm, $fingerprint)';
}
