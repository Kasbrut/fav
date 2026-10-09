import 'package:fav/core/crypto/ed25519_keypair.dart';
import 'package:fav/features/install/data/keys/ssh_key_repository.dart';

/// [SshKeyRepository] fake that always returns the same key pair.
///
/// Lets the SSH auth resolver pick the key-only authentication path, so tests
/// can exercise SSH flows without supplying (or fabricating) a login password.
class FakeSshKeyRepository implements SshKeyRepository {
  /// Creates a [FakeSshKeyRepository] returning [_keyPair] for every server.
  FakeSshKeyRepository(this._keyPair);

  final Ed25519KeyPair _keyPair;

  @override
  Future<Ed25519KeyPair?> get(String serverId) async => _keyPair;

  @override
  Future<Ed25519KeyPair> getOrCreate({
    required String serverId,
    required String comment,
  }) async => _keyPair;

  @override
  Future<void> delete(String serverId) async {}
}
