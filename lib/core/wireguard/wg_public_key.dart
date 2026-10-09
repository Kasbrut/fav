import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:meta/meta.dart';

/// A WireGuard public key in its canonical form (X25519, standard base64,
/// 44 characters including the trailing `=` padding).
///
/// Centralizes the normalization rules so peers reported by the monitoring
/// agent (`wg show wg0 dump`) can be matched reliably against the client's
/// own public key derived from its private key, and against the labels we
/// store locally (`PeerSummary.publicKey`, monitoring events). Created by
/// [WgPublicKey.parse] for inputs we receive, or [WgPublicKey.fromPrivateKey]
/// to derive it ourselves.
@immutable
class WgPublicKey {
  const WgPublicKey._(this.canonical);

  /// Parses [raw] into a [WgPublicKey], trimming surrounding whitespace.
  ///
  /// Throws [FormatException] when [raw] is not 44 characters or does not
  /// decode (standard base64) to 32 bytes.
  factory WgPublicKey.parse(String raw) {
    final trimmed = raw.trim();
    if (trimmed.length != 44) {
      throw FormatException(
        'WireGuard public key must be 44 characters (got ${trimmed.length})',
      );
    }
    final List<int> bytes;
    try {
      bytes = base64.decode(trimmed);
    } on FormatException {
      throw const FormatException(
        'WireGuard public key is not valid base64',
      );
    }
    if (bytes.length != 32) {
      throw FormatException(
        'WireGuard public key must decode to 32 bytes (got ${bytes.length})',
      );
    }
    return WgPublicKey._(trimmed);
  }

  /// Standard-base64 representation, 44 chars including padding.
  final String canonical;

  /// Derives the public key from the WireGuard [privateKey] (X25519).
  ///
  /// [privateKey] is the standard-base64 form produced by `wg genkey` (44
  /// chars). Uses [base64Encode] from `dart:convert` — NOT
  /// `base64UrlEncode` — so the canonical output matches `wg pubkey`.
  ///
  /// Throws [FormatException] when [privateKey] does not decode to 32 bytes.
  static Future<WgPublicKey> fromPrivateKey(String privateKey) async {
    final List<int> seed;
    try {
      seed = base64.decode(privateKey.trim());
    } on FormatException {
      throw const FormatException(
        'WireGuard private key is not valid base64',
      );
    }
    if (seed.length != 32) {
      throw FormatException(
        'WireGuard private key must decode to 32 bytes (got ${seed.length})',
      );
    }
    final keyPair = await X25519().newKeyPairFromSeed(seed);
    final publicKey = await keyPair.extractPublicKey();
    return WgPublicKey._(base64.encode(publicKey.bytes));
  }

  @override
  bool operator ==(Object other) =>
      other is WgPublicKey && other.canonical == canonical;

  @override
  int get hashCode => canonical.hashCode;

  @override
  String toString() => canonical;
}
