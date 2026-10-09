import 'package:meta/meta.dart';

/// A pinned SSH host key fingerprint.
///
/// Stored on the first connection (Trust On First Use) and verified on every
/// later connection; a mismatch is blocked as a possible MITM (spec §10).
@immutable
class HostKeyFingerprint {
  /// Creates a [HostKeyFingerprint].
  const HostKeyFingerprint({
    required this.host,
    required this.port,
    required this.keyType,
    required this.hashAlgorithm,
    required this.fingerprint,
    required this.pinnedAt,
  });

  /// IP address or hostname the key belongs to.
  final String host;

  /// SSH port the key belongs to.
  final int port;

  /// SSH host key type (for example `ssh-ed25519`).
  final String keyType;

  /// Hash algorithm of [fingerprint]: `sha256` since dartssh2 3.x; pins
  /// stored by earlier app versions carry `md5`. The explicit algorithm is
  /// what lets `evaluateHostKey` detect an incomparable legacy pin and
  /// trigger an explicit re-confirmation instead of a false MITM alarm.
  final String hashAlgorithm;

  /// The host key fingerprint value: OpenSSH-style base64 (no `SHA256:`
  /// prefix) for sha256, colon-separated lowercase hex for legacy md5 pins.
  final String fingerprint;

  /// When the fingerprint was pinned.
  final DateTime pinnedAt;

  /// Returns a copy of this fingerprint with the given fields replaced.
  HostKeyFingerprint copyWith({
    String? host,
    int? port,
    String? keyType,
    String? hashAlgorithm,
    String? fingerprint,
    DateTime? pinnedAt,
  }) {
    return HostKeyFingerprint(
      host: host ?? this.host,
      port: port ?? this.port,
      keyType: keyType ?? this.keyType,
      hashAlgorithm: hashAlgorithm ?? this.hashAlgorithm,
      fingerprint: fingerprint ?? this.fingerprint,
      pinnedAt: pinnedAt ?? this.pinnedAt,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is HostKeyFingerprint &&
        other.host == host &&
        other.port == port &&
        other.keyType == keyType &&
        other.hashAlgorithm == hashAlgorithm &&
        other.fingerprint == fingerprint &&
        other.pinnedAt == pinnedAt;
  }

  @override
  int get hashCode {
    return Object.hash(
      host,
      port,
      keyType,
      hashAlgorithm,
      fingerprint,
      pinnedAt,
    );
  }
}
