import 'dart:convert';

import 'package:fav/core/crypto/sha256_hasher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('sha256Hex', () {
    test('hashes an empty input', () {
      expect(
        sha256Hex(const <int>[]),
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
      );
    });

    test('hashes the standard "abc" vector', () {
      expect(
        sha256Hex(utf8.encode('abc')),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
    });

    test('is stable across calls', () {
      final data = utf8.encode('wireguard');
      expect(sha256Hex(data), sha256Hex(data));
    });
  });
}
