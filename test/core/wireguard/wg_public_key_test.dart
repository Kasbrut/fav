import 'package:fav/core/wireguard/wg_public_key.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 32-byte all-zero seed (base64): a deterministic input the test can pin
  // outputs against without depending on `wg pubkey` being installed locally.
  // The lab-VM verification in M15-T9 cross-checks at least one (priv, pub)
  // pair against the real `wg pubkey` output.
  const allZeroPrivate = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=';

  group('WgPublicKey.parse', () {
    test('accepts a 44-character standard-base64 key and trims whitespace', () {
      const raw = '  AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=  ';
      final key = WgPublicKey.parse(raw);
      expect(key.canonical, 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=');
    });

    test('rejects a key shorter than 44 characters', () {
      expect(
        () => WgPublicKey.parse('tooshort'),
        throwsFormatException,
      );
    });

    test('rejects a key that is not valid base64', () {
      expect(
        () => WgPublicKey.parse('!' * 44),
        throwsFormatException,
      );
    });

    test('rejects a key whose decoded length is not 32 bytes', () {
      // 44 chars of "A" decodes to 33 bytes (32 + the implicit trailing 0
      // padding byte), which is rejected.
      expect(
        () => WgPublicKey.parse('A' * 44),
        throwsFormatException,
      );
    });
  });

  group('WgPublicKey.fromPrivateKey', () {
    test('derives a 44-char standard-base64 public key', () async {
      final key = await WgPublicKey.fromPrivateKey(allZeroPrivate);
      expect(key.canonical, hasLength(44));
      expect(key.canonical.endsWith('='), isTrue);
      // Standard base64 only — must not contain URL-safe characters.
      expect(key.canonical.contains('-'), isFalse);
      expect(key.canonical.contains('_'), isFalse);
    });

    test('is deterministic for the same input', () async {
      final a = await WgPublicKey.fromPrivateKey(allZeroPrivate);
      final b = await WgPublicKey.fromPrivateKey(allZeroPrivate);
      expect(a, equals(b));
    });

    test('produces different public keys for different private keys', () async {
      const other = 'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBA=';
      final a = await WgPublicKey.fromPrivateKey(allZeroPrivate);
      final b = await WgPublicKey.fromPrivateKey(other);
      expect(a, isNot(equals(b)));
    });

    test('rejects a private key that does not decode to 32 bytes', () async {
      await expectLater(
        WgPublicKey.fromPrivateKey('AAAA'),
        throwsFormatException,
      );
    });

    test('rejects a private key that is not valid base64', () async {
      await expectLater(
        WgPublicKey.fromPrivateKey('!' * 44),
        throwsFormatException,
      );
    });
  });

  group('WgPublicKey equality', () {
    test('two parses of the same canonical form are equal', () {
      final a = WgPublicKey.parse(
        'WAfFTjvT/u6L8E+9I4yz+8c8mWAfFTjvT/u6L8E+9Iw=',
      );
      final b = WgPublicKey.parse(
        'WAfFTjvT/u6L8E+9I4yz+8c8mWAfFTjvT/u6L8E+9Iw=',
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('toString returns the canonical form', () {
      final key = WgPublicKey.parse(
        'WAfFTjvT/u6L8E+9I4yz+8c8mWAfFTjvT/u6L8E+9Iw=',
      );
      expect(key.toString(), 'WAfFTjvT/u6L8E+9I4yz+8c8mWAfFTjvT/u6L8E+9Iw=');
    });
  });
}
