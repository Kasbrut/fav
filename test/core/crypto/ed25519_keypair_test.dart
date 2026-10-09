import 'dart:typed_data';

import 'package:fav/core/crypto/ed25519_keypair.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Ed25519KeyPair', () {
    test('generate produces a 32+32 byte pair', () async {
      final keyPair = await Ed25519KeyPair.generate();
      expect(keyPair.seedBytes, hasLength(32));
      expect(keyPair.publicKeyBytes, hasLength(32));
    });

    test('expandedPrivateKey is seed || pubkey (64 bytes)', () async {
      final keyPair = await Ed25519KeyPair.generate();
      expect(keyPair.expandedPrivateKey, hasLength(64));
      expect(
        keyPair.expandedPrivateKey.sublist(0, 32),
        keyPair.seedBytes,
      );
      expect(
        keyPair.expandedPrivateKey.sublist(32, 64),
        keyPair.publicKeyBytes,
      );
    });

    test('fromSeed is deterministic in the public key', () async {
      final seed = Uint8List.fromList(List<int>.generate(32, (i) => i + 1));
      final a = await Ed25519KeyPair.fromSeed(seed);
      final b = await Ed25519KeyPair.fromSeed(seed);
      expect(a.publicKeyBytes, b.publicKeyBytes);
      expect(a.seedBytes, b.seedBytes);
    });

    test('fromSeed rejects a wrong-length seed', () async {
      await expectLater(
        Ed25519KeyPair.fromSeed(Uint8List.fromList([1, 2, 3])),
        throwsArgumentError,
      );
    });

    test('authorizedKeysEntry has the OpenSSH shape', () async {
      // RFC-aligned: the entry is `ssh-ed25519 BASE64 comment` and the
      // base64 part decodes to `string("ssh-ed25519") || string(32-byte pk)`.
      final keyPair = await Ed25519KeyPair.generate();
      final entry = keyPair.authorizedKeysEntry(comment: 'wg-prov@id');
      final parts = entry.split(' ');
      expect(parts, hasLength(3));
      expect(parts[0], 'ssh-ed25519');
      expect(parts[2], 'wg-prov@id');
      // The blob is 4 + 11 ("ssh-ed25519") + 4 + 32 = 51 bytes; base64 of 51
      // bytes is 68 characters with padding.
      expect(parts[1].length, 68);
    });

    test('authorizedKeysEntry rejects a comment with whitespace', () async {
      final keyPair = await Ed25519KeyPair.generate();
      expect(
        () => keyPair.authorizedKeysEntry(comment: 'two words'),
        throwsArgumentError,
      );
    });

    test('toString redacts the seed', () async {
      final keyPair = await Ed25519KeyPair.generate();
      final text = keyPair.toString();
      expect(text, contains('redacted'));
      // The string should be short enough that it cannot embed 64 hex chars
      // or 44 base64 chars worth of seed material.
      expect(text.length, lessThan(64));
    });
  });
}
