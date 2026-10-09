import 'dart:convert';

import 'package:fav/core/persistence/secure_store.dart';
import 'package:fav/features/servers/domain/host_key_fingerprint.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';

/// Canonical shape of a dartssh2 3.x fingerprint payload: the OpenSSH-style
/// prefix plus exactly 43 unpadded base64 characters of a SHA-256 digest.
final RegExp _sha256HandlerFormat = RegExp(r'^SHA256:[A-Za-z0-9+/]{43}$');

/// Decodes the fingerprint bytes handed out by dartssh2 3.x: the UTF-8
/// encoding of the OpenSSH-style `SHA256:<base64>` string. The prefix is
/// stripped — the UI renders the algorithm label in front of the value, and
/// storing it twice would double it.
///
/// Returns `null` — fail closed, the caller must refuse the connection —
/// for anything but the canonical format: the pin is a trust anchor, and a
/// lossily-decoded or unparsed value could collapse distinct fingerprints
/// into one stored string (security audit M2 on the 3.x migration).
String? sha256FingerprintFromHandler(List<int> bytes) {
  final String decoded;
  try {
    decoded = utf8.decode(bytes);
  } on FormatException {
    return null;
  }
  if (!_sha256HandlerFormat.hasMatch(decoded)) {
    return null;
  }
  return decoded.substring('SHA256:'.length);
}

/// Outcome of comparing a received host key against the pinned one.
enum HostKeyDecision {
  /// The received key matches the pinned one.
  accept,

  /// No key has been pinned yet for this host (Trust On First Use).
  unknown,

  /// The received key differs from the pinned one (possible MITM).
  mismatch,

  /// The pinned fingerprint uses a different hash algorithm than the
  /// received one, so they cannot be compared: pins stored by the
  /// dartssh2 2.x app are MD5, the 3.x library hands out SHA-256 only.
  /// Callers must re-run the explicit TOFU confirmation (the fingerprint
  /// is shown to the user, verifiable out-of-band) and re-pin — never
  /// silently accept, and never report it as a MITM mismatch.
  algorithmChanged,
}

/// Decides whether a [received] host key is trusted, given the [pinned] one.
HostKeyDecision evaluateHostKey({
  required HostKeyFingerprint received,
  required HostKeyFingerprint? pinned,
}) {
  if (pinned == null) {
    return HostKeyDecision.unknown;
  }
  if (pinned.hashAlgorithm != received.hashAlgorithm) {
    return HostKeyDecision.algorithmChanged;
  }
  // The fingerprint alone decides: it hashes the host key blob, which
  // already encodes the key type. keyType is the negotiated *signature*
  // algorithm — the same RSA key can present as rsa-sha2-256 or
  // rsa-sha2-512 — so comparing it would raise false MITM alarms
  // (security audit L1); it is kept for display only.
  return pinned.fingerprint == received.fingerprint
      ? HostKeyDecision.accept
      : HostKeyDecision.mismatch;
}

/// First 8 characters of a fingerprint, for identifying-but-not-indexable
/// log lines: a full host-key fingerprint is a Censys/Shodan lookup key
/// back to the host (audit H1).
String _fingerprintPrefix(String fingerprint) =>
    fingerprint.length <= 8 ? fingerprint : fingerprint.substring(0, 8);

/// Outcome of verifying one received host key during the SSH handshake:
/// the accept/refuse decision plus the side effects the client must apply.
class HostKeyVerification {
  /// Creates a verification outcome.
  const HostKeyVerification({
    required this.accept,
    this.pendingKey,
    this.mismatchedKey,
    this.previouslyTrusted = false,
    this.mismatch = false,
  });

  /// Whether the handshake may proceed.
  final bool accept;

  /// The received fingerprint when an explicit TOFU confirmation is needed;
  /// null when accepted or refused as a mismatch.
  final HostKeyFingerprint? pendingKey;

  /// The received fingerprint when it differs from the active pin.
  final HostKeyFingerprint? mismatchedKey;

  /// True when [pendingKey] replaces an incomparable legacy (MD5-era) pin —
  /// the confirmation dialog uses the "trusted before" copy.
  final bool previouslyTrusted;

  /// True when the connection must be refused as a possible MITM. Also the
  /// fail-closed answer for an unparseable fingerprint payload (audit M2 on
  /// the 3.x migration): an uncomparable value must never be pinned.
  final bool mismatch;
}

/// Verifies the host key dartssh2 hands to `onVerifyHostKey` against the
/// [pinned] fingerprint. Pure decision logic extracted from the client so
/// every arm is unit-testable (migration audit L4); the caller applies the
/// returned side effects and answers with [HostKeyVerification.accept].
///
/// [fingerprintBytes] is the raw handler payload — the UTF-8 encoding of
/// the OpenSSH-style `SHA256:<base64>` string (matches what
/// `ssh-keygen -lf` prints, so the user can verify it out-of-band; closes
/// audit M-md5). Log lines carry at most an 8-char fingerprint prefix.
HostKeyVerification verifyReceivedHostKey({
  required String host,
  required int port,
  required String keyType,
  required List<int> fingerprintBytes,
  required HostKeyFingerprint? pinned,
  required Logger logger,
}) {
  final decoded = sha256FingerprintFromHandler(fingerprintBytes);
  if (decoded == null) {
    logger.w(
      'Host key fingerprint for $host:$port arrived '
      'in an unexpected format — refusing the connection',
    );
    return const HostKeyVerification(accept: false, mismatch: true);
  }
  final received = HostKeyFingerprint(
    host: host,
    port: port,
    keyType: keyType,
    hashAlgorithm: 'sha256',
    fingerprint: decoded,
    pinnedAt: DateTime.now(),
  );
  switch (evaluateHostKey(received: received, pinned: pinned)) {
    case HostKeyDecision.accept:
      logger.d('Host key accepted for $host:$port ($keyType, pinned)');
      return const HostKeyVerification(accept: true);
    case HostKeyDecision.unknown:
      logger.i(
        'Host key unknown for $host:$port — TOFU confirmation needed '
        '($keyType sha256 ${_fingerprintPrefix(decoded)}…)',
      );
      return HostKeyVerification(accept: false, pendingKey: received);
    case HostKeyDecision.algorithmChanged:
      // An MD5-era pin cannot be compared against the SHA-256 fingerprint:
      // fall back to the explicit TOFU confirmation so the user re-verifies
      // and the pin upgrades — never silently.
      logger.w(
        'Host key pin for $host:$port predates the SHA-256 fingerprints — '
        're-confirmation needed ($keyType sha256 '
        '${_fingerprintPrefix(decoded)}…)',
      );
      return HostKeyVerification(
        accept: false,
        pendingKey: received,
        previouslyTrusted: true,
      );
    case HostKeyDecision.mismatch:
      logger.w(
        'Host key MISMATCH for $host:$port — possible MITM '
        '(received $keyType sha256 ${_fingerprintPrefix(decoded)}…)',
      );
      return HostKeyVerification(
        accept: false,
        mismatch: true,
        mismatchedKey: received,
      );
  }
}

/// Persists pinned host key fingerprints, one secure-storage entry per
/// `host:port` (spec §4.2).
class HostKeyStore {
  /// Creates a [HostKeyStore] backed by the given secure store.
  HostKeyStore(this._secureStore);

  final SecureStore _secureStore;

  /// Returns the pinned fingerprint for [host]:[port], or `null` if none.
  Future<HostKeyFingerprint?> lookup(String host, int port) async {
    final raw = await _secureStore.read(_entryKey(host, port));
    if (raw == null) {
      return null;
    }
    return _fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  /// Pins [fingerprint], replacing any previous entry for the same host:port.
  Future<void> pin(HostKeyFingerprint fingerprint) {
    return _secureStore.write(
      _entryKey(fingerprint.host, fingerprint.port),
      jsonEncode(_toJson(fingerprint)),
    );
  }

  /// Removes the pinned fingerprint for [host]:[port].
  Future<void> delete(String host, int port) {
    return _secureStore.delete(_entryKey(host, port));
  }

  String _entryKey(String host, int port) => 'hostkey:$host:$port';

  Map<String, Object?> _toJson(HostKeyFingerprint fingerprint) => {
    'host': fingerprint.host,
    'port': fingerprint.port,
    'keyType': fingerprint.keyType,
    'hashAlgorithm': fingerprint.hashAlgorithm,
    'fingerprint': fingerprint.fingerprint,
    'pinnedAt': fingerprint.pinnedAt.toIso8601String(),
  };

  HostKeyFingerprint _fromJson(Map<String, dynamic> json) {
    return HostKeyFingerprint(
      host: json['host'] as String,
      port: json['port'] as int,
      keyType: json['keyType'] as String,
      hashAlgorithm: json['hashAlgorithm'] as String,
      fingerprint: json['fingerprint'] as String,
      pinnedAt: DateTime.parse(json['pinnedAt'] as String),
    );
  }
}

/// Provides the [HostKeyStore].
final Provider<HostKeyStore> hostKeyStoreProvider = Provider<HostKeyStore>(
  (ref) => HostKeyStore(ref.watch(secureStoreProvider)),
);
