import 'dart:convert';
import 'dart:typed_data';

import 'package:fav/core/crypto/ed25519_keypair.dart';
import 'package:fav/core/persistence/secure_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Storage of the Ed25519 SSH key pair generated for the optional hardening
/// flow (spec §10.3).
///
/// Only the 32-byte seed lives in the secure store, base64-encoded under a
/// per-server key. The public key is recomputed at read time. The seed never
/// reaches the UI, logs, or any non-secure persistence.
abstract interface class SshKeyRepository {
  /// Returns the existing key pair for [serverId], or generates and stores a
  /// new one. [comment] is the suffix written into `authorized_keys` for the
  /// generated key (typically `fav@<serverId>`); it is
  /// ignored when an existing key is returned (it has no effect on the bytes).
  Future<Ed25519KeyPair> getOrCreate({
    required String serverId,
    required String comment,
  });

  /// Returns the existing key pair for [serverId], or `null` if none exists.
  Future<Ed25519KeyPair?> get(String serverId);

  /// Removes the stored key pair for [serverId], if any.
  Future<void> delete(String serverId);
}

/// [SshKeyRepository] backed by the OS keystore via [SecureStore].
class SecureSshKeyRepository implements SshKeyRepository {
  /// Creates a [SecureSshKeyRepository] over [_store].
  const SecureSshKeyRepository(this._store);

  /// Key prefix used in the secure store; the suffix is the server id.
  static const String _keyPrefix = 'ssh-key:';

  final SecureStore _store;

  String _key(String serverId) => '$_keyPrefix$serverId';

  @override
  Future<Ed25519KeyPair> getOrCreate({
    required String serverId,
    required String comment,
  }) async {
    final existing = await get(serverId);
    if (existing != null) {
      return existing;
    }
    final keyPair = await Ed25519KeyPair.generate();
    await _store.write(_key(serverId), base64.encode(keyPair.seedBytes));
    return keyPair;
  }

  @override
  Future<Ed25519KeyPair?> get(String serverId) async {
    final encoded = await _store.read(_key(serverId));
    if (encoded == null || encoded.isEmpty) {
      return null;
    }
    final Uint8List seed;
    try {
      seed = Uint8List.fromList(base64.decode(encoded));
    } on FormatException {
      // Never rethrow the original: FormatException.toString() embeds its
      // source — the base64 of the PRIVATE seed — and the error propagates
      // into rendered/logged technical detail (same class as audit H2 on
      // the DB encryption key).
      throw const FormatException('stored SSH key seed is not valid base64');
    }
    return Ed25519KeyPair.fromSeed(seed);
  }

  @override
  Future<void> delete(String serverId) => _store.delete(_key(serverId));
}

/// Provides the [SshKeyRepository] backed by [SecureStore].
final Provider<SshKeyRepository> sshKeyRepositoryProvider =
    Provider<SshKeyRepository>(
      (ref) => SecureSshKeyRepository(ref.watch(secureStoreProvider)),
    );
