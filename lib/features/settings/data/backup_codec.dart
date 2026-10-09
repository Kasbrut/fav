import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Current on-disk format for encrypted FAV backups.
const int favBackupFormatVersion = 1;

/// Failure to decode, authenticate or decrypt a FAV backup.
class BackupFormatException implements Exception {
  /// Creates a safe error that never contains key material or ciphertext.
  const BackupFormatException(this.message);

  /// User-safe diagnostic detail.
  final String message;

  @override
  String toString() => 'BackupFormatException($message)';
}

/// Password-based authenticated encryption for backup payloads.
class BackupCodec {
  /// Creates a codec. Reduced parameters may be injected by unit tests.
  BackupCodec({
    this._memoryKiB = 64 * 1024,
    this._iterations = 3,
    this._parallelism = 1,
    Random? random,
  }) : _random = random ?? Random.secure();

  final int _memoryKiB;
  final int _iterations;
  final int _parallelism;
  final Random _random;

  /// Encrypts a JSON-shaped backup [payload] using [password].
  Future<Uint8List> encrypt({
    required Map<String, Object?> payload,
    required String password,
  }) async {
    if (password.isEmpty) {
      throw const BackupFormatException('backup password is empty');
    }
    final salt = _randomBytes(16);
    final key = await _deriveKey(password: password, salt: salt);
    final cipher = AesGcm.with256bits();
    final box = await cipher.encrypt(
      utf8.encode(jsonEncode(payload)),
      secretKey: key,
    );
    final envelope = <String, Object?>{
      'magic': 'FAV-BACKUP',
      'formatVersion': favBackupFormatVersion,
      'kdf': <String, Object?>{
        'name': 'argon2id',
        'memoryKiB': _memoryKiB,
        'iterations': _iterations,
        'parallelism': _parallelism,
        'salt': base64Encode(salt),
      },
      'cipher': <String, Object?>{
        'name': 'aes-256-gcm',
        'nonce': base64Encode(box.nonce),
        'cipherText': base64Encode(box.cipherText),
        'mac': base64Encode(box.mac.bytes),
      },
    };
    return Uint8List.fromList(utf8.encode(jsonEncode(envelope)));
  }

  /// Authenticates and decrypts [bytes] using [password].
  Future<Map<String, dynamic>> decrypt({
    required List<int> bytes,
    required String password,
  }) async {
    if (bytes.length > 20 * 1024 * 1024) {
      throw const BackupFormatException('backup file is too large');
    }
    try {
      final envelope = jsonDecode(utf8.decode(bytes));
      if (envelope is! Map<String, dynamic> ||
          envelope['magic'] != 'FAV-BACKUP' ||
          envelope['formatVersion'] != favBackupFormatVersion) {
        throw const BackupFormatException('unsupported backup file');
      }
      final kdf = envelope['kdf'] as Map<String, dynamic>;
      final cipherData = envelope['cipher'] as Map<String, dynamic>;
      if (kdf['name'] != 'argon2id' || cipherData['name'] != 'aes-256-gcm') {
        throw const BackupFormatException('unsupported backup encryption');
      }
      final memory = kdf['memoryKiB'] as int;
      final iterations = kdf['iterations'] as int;
      final parallelism = kdf['parallelism'] as int;
      if (memory < 8 * 1024 ||
          memory > 256 * 1024 ||
          iterations < 1 ||
          iterations > 10 ||
          parallelism < 1 ||
          parallelism > 8) {
        throw const BackupFormatException('invalid backup parameters');
      }
      final salt = base64Decode(kdf['salt'] as String);
      final key = await _deriveKey(
        password: password,
        salt: salt,
        memoryKiB: memory,
        iterations: iterations,
        parallelism: parallelism,
      );
      final box = SecretBox(
        base64Decode(cipherData['cipherText'] as String),
        nonce: base64Decode(cipherData['nonce'] as String),
        mac: Mac(base64Decode(cipherData['mac'] as String)),
      );
      final clear = await AesGcm.with256bits().decrypt(box, secretKey: key);
      final payload = jsonDecode(utf8.decode(clear));
      if (payload is! Map<String, dynamic>) {
        throw const BackupFormatException('invalid backup contents');
      }
      return payload;
    } on BackupFormatException {
      rethrow;
    } on Object {
      throw const BackupFormatException(
        'incorrect password or damaged backup',
      );
    }
  }

  Future<SecretKey> _deriveKey({
    required String password,
    required List<int> salt,
    int? memoryKiB,
    int? iterations,
    int? parallelism,
  }) {
    return Argon2id(
      parallelism: parallelism ?? _parallelism,
      memory: memoryKiB ?? _memoryKiB,
      iterations: iterations ?? _iterations,
      hashLength: 32,
    ).deriveKey(secretKey: SecretKey(utf8.encode(password)), nonce: salt);
  }

  Uint8List _randomBytes(int length) => Uint8List.fromList(
    List<int>.generate(length, (_) => _random.nextInt(256)),
  );
}
