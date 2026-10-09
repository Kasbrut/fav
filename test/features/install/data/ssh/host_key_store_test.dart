import 'dart:convert';

import 'package:fav/features/install/data/ssh/host_key_store.dart';
import 'package:fav/features/servers/domain/host_key_fingerprint.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';

import '../../../../support/in_memory_secure_store.dart';

/// Tests for fingerprint formatting, the TOFU decision and [HostKeyStore].
/// Captures log lines so tests can assert what reaches the log.
class _MemoryLogOutput extends LogOutput {
  final List<String> lines = [];

  @override
  void output(OutputEvent event) => lines.addAll(event.lines);
}

void main() {
  HostKeyFingerprint fingerprint({
    String value = 'aa:bb:cc',
    String algorithm = 'md5',
  }) {
    return HostKeyFingerprint(
      host: '203.0.113.5',
      port: 22,
      keyType: 'ssh-ed25519',
      hashAlgorithm: algorithm,
      fingerprint: value,
      pinnedAt: DateTime(2026, 5, 18),
    );
  }

  group('sha256FingerprintFromHandler', () {
    // A canonical dartssh2 3.x payload: SHA256: + exactly 43 base64 chars
    // (an unpadded SHA-256 digest).
    const value = 'AbCdEfGh01234567890123456789012345678901+/x';
    const canonical = 'SHA256:$value';

    test('decodes the dartssh2 3.x bytes and strips the prefix', () {
      // The prefix is stripped so it is not doubled by the algorithm label
      // the dialog renders in front of the value.
      expect(value, hasLength(43));
      expect(sha256FingerprintFromHandler(utf8.encode(canonical)), value);
    });

    test('fails closed on anything but the canonical format', () {
      // The stored pin is a trust anchor: an unparsed or lossily-decoded
      // value could collapse distinct fingerprints into one string
      // (security audit M2 on the 3.x migration). Reject instead.
      expect(sha256FingerprintFromHandler(utf8.encode('AbCdEf012')), isNull);
      expect(
        sha256FingerprintFromHandler(utf8.encode('SHA256:short')),
        isNull,
      );
      expect(
        sha256FingerprintFromHandler(utf8.encode('MD5:aa:bb:cc')),
        isNull,
      );
      // Invalid UTF-8 must not be lossily accepted.
      expect(sha256FingerprintFromHandler([0xff, 0xfe, 0x00]), isNull);
    });
  });

  group('evaluateHostKey', () {
    test('unknown when nothing is pinned', () {
      expect(
        evaluateHostKey(received: fingerprint(), pinned: null),
        HostKeyDecision.unknown,
      );
    });

    test('accept when the pinned key matches', () {
      expect(
        evaluateHostKey(received: fingerprint(), pinned: fingerprint()),
        HostKeyDecision.accept,
      );
    });

    test('mismatch when the pinned key differs', () {
      expect(
        evaluateHostKey(
          received: fingerprint(),
          pinned: fingerprint(value: 'ff:ff:ff'),
        ),
        HostKeyDecision.mismatch,
      );
    });

    test('algorithmChanged when an md5-era pin meets a sha256 key', () {
      // dartssh2 3.x hands out SHA-256 fingerprints; pins stored by the 2.x
      // app are MD5 and cannot be compared. That is neither a mismatch (the
      // error copy would claim a MITM) nor a silent accept — the user must
      // re-confirm the new fingerprint (re-TOFU).
      expect(
        evaluateHostKey(
          received: fingerprint(value: 'AbCdEf012', algorithm: 'sha256'),
          pinned: fingerprint(),
        ),
        HostKeyDecision.algorithmChanged,
      );
    });

    test('sha256 pins keep the normal accept/mismatch semantics', () {
      expect(
        evaluateHostKey(
          received: fingerprint(value: 'AbCdEf012', algorithm: 'sha256'),
          pinned: fingerprint(value: 'AbCdEf012', algorithm: 'sha256'),
        ),
        HostKeyDecision.accept,
      );
      expect(
        evaluateHostKey(
          received: fingerprint(value: 'AbCdEf012', algorithm: 'sha256'),
          pinned: fingerprint(value: 'Different', algorithm: 'sha256'),
        ),
        HostKeyDecision.mismatch,
      );
    });

    test('a differing signature-algorithm name alone does not mismatch', () {
      // keyType is the negotiated *signature* algorithm: the same RSA host
      // key can present as rsa-sha2-256 or rsa-sha2-512 with an identical
      // fingerprint. The fingerprint hashes the key blob (which already
      // encodes the type), so it alone decides (security audit L1).
      final pinned = HostKeyFingerprint(
        host: '203.0.113.5',
        port: 22,
        keyType: 'rsa-sha2-256',
        hashAlgorithm: 'sha256',
        fingerprint: 'SameFp',
        pinnedAt: DateTime(2026, 8, 19),
      );
      expect(
        evaluateHostKey(
          received: pinned.copyWith(keyType: 'rsa-sha2-512'),
          pinned: pinned,
        ),
        HostKeyDecision.accept,
      );
    });
  });

  group('verifyReceivedHostKey', () {
    // Canonical dartssh2 3.x payload: UTF-8 of `SHA256:` + 43 base64 chars.
    final fortyThree = 'A' * 43;
    final otherFortyThree = 'B' * 43;
    List<int> handlerBytes(String base64) => utf8.encode('SHA256:$base64');

    HostKeyFingerprint pinnedWith({
      String? fingerprint,
      String hashAlgorithm = 'sha256',
    }) {
      return HostKeyFingerprint(
        host: '203.0.113.5',
        port: 22,
        keyType: 'ssh-ed25519',
        hashAlgorithm: hashAlgorithm,
        fingerprint: fingerprint ?? fortyThree,
        pinnedAt: DateTime.utc(2026),
      );
    }

    (_MemoryLogOutput, Logger) memoryLogger() {
      final output = _MemoryLogOutput();
      final logger = Logger(
        output: output,
        printer: SimplePrinter(),
        filter: ProductionFilter(),
        level: Level.all,
      );
      return (output, logger);
    }

    HostKeyVerification verify({
      required HostKeyFingerprint? pinned,
      List<int>? bytes,
      Logger? logger,
    }) {
      return verifyReceivedHostKey(
        host: '203.0.113.5',
        port: 22,
        keyType: 'ssh-ed25519',
        fingerprintBytes: bytes ?? handlerBytes(fortyThree),
        pinned: pinned,
        logger: logger ?? memoryLogger().$2,
      );
    }

    test('no pin → confirmation needed, first connection', () {
      final verification = verify(pinned: null);
      expect(verification.accept, isFalse);
      expect(verification.mismatch, isFalse);
      expect(verification.previouslyTrusted, isFalse);
      expect(verification.pendingKey?.fingerprint, fortyThree);
      expect(verification.pendingKey?.hashAlgorithm, 'sha256');
      expect(verification.pendingKey?.keyType, 'ssh-ed25519');
    });

    test('matching pin → accepted, no side effects', () {
      final verification = verify(pinned: pinnedWith());
      expect(verification.accept, isTrue);
      expect(verification.mismatch, isFalse);
      expect(verification.pendingKey, isNull);
    });

    test('different fingerprint → mismatch, never a pending key', () {
      final verification = verify(
        pinned: pinnedWith(fingerprint: otherFortyThree),
      );
      expect(verification.accept, isFalse);
      expect(verification.mismatch, isTrue);
      expect(verification.pendingKey, isNull);
      expect(verification.mismatchedKey?.fingerprint, fortyThree);
    });

    test('legacy MD5 pin → re-confirmation marked previously trusted', () {
      final verification = verify(
        pinned: pinnedWith(hashAlgorithm: 'md5', fingerprint: 'aa:bb:cc'),
      );
      expect(verification.accept, isFalse);
      expect(verification.mismatch, isFalse);
      expect(verification.previouslyTrusted, isTrue);
      expect(verification.pendingKey?.fingerprint, fortyThree);
    });

    test('unparseable payload fails closed as a mismatch', () {
      final verification = verify(bytes: [0xFF, 0xFE], pinned: null);
      expect(verification.accept, isFalse);
      expect(verification.mismatch, isTrue);
      expect(verification.pendingKey, isNull);
      expect(verification.mismatchedKey, isNull);
    });

    test('logs carry only an 8-char fingerprint prefix (audit H1)', () {
      final (output, logger) = memoryLogger();
      verify(pinned: null, logger: logger);
      final joined = output.lines.join('\n');
      expect(joined, contains(fortyThree.substring(0, 8)));
      expect(joined, isNot(contains(fortyThree)));
    });
  });

  group('HostKeyStore', () {
    test('pin then lookup returns the stored fingerprint', () async {
      final store = HostKeyStore(InMemorySecureStore());
      expect(await store.lookup('203.0.113.5', 22), isNull);
      await store.pin(fingerprint());
      expect(await store.lookup('203.0.113.5', 22), equals(fingerprint()));
    });

    test('delete removes the pinned fingerprint', () async {
      final store = HostKeyStore(InMemorySecureStore());
      await store.pin(fingerprint());
      await store.delete('203.0.113.5', 22);
      expect(await store.lookup('203.0.113.5', 22), isNull);
    });
  });
}
