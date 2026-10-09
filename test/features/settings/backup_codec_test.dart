import 'dart:math';

import 'package:fav/features/settings/data/backup_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  BackupCodec codec() => BackupCodec(
    memoryKiB: 8 * 1024,
    iterations: 1,
    random: Random(42),
  );

  test('round-trips an authenticated payload', () async {
    final bytes = await codec().encrypt(
      payload: <String, Object?>{
        'schemaVersion': 1,
        'server': <String, Object?>{'label': 'Test'},
      },
      password: 'a strong transfer password',
    );

    final decoded = await codec().decrypt(
      bytes: bytes,
      password: 'a strong transfer password',
    );

    expect(decoded['schemaVersion'], 1);
    expect((decoded['server'] as Map<String, dynamic>)['label'], 'Test');
  });

  test('rejects an incorrect password without leaking details', () async {
    final bytes = await codec().encrypt(
      payload: <String, Object?>{'schemaVersion': 1},
      password: 'correct password',
    );

    await expectLater(
      codec().decrypt(bytes: bytes, password: 'wrong password'),
      throwsA(
        isA<BackupFormatException>().having(
          (error) => error.message,
          'message',
          'incorrect password or damaged backup',
        ),
      ),
    );
  });

  test('rejects tampered ciphertext', () async {
    final bytes = await codec().encrypt(
      payload: <String, Object?>{'schemaVersion': 1},
      password: 'correct password',
    );
    bytes[bytes.length ~/ 2] ^= 1;

    await expectLater(
      codec().decrypt(bytes: bytes, password: 'correct password'),
      throwsA(isA<BackupFormatException>()),
    );
  });
}
