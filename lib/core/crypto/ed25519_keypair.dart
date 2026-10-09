import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart' as crypto;
import 'package:dartssh2/dartssh2.dart' as ssh;
import 'package:meta/meta.dart';

/// An Ed25519 key pair generated client-side for the optional SSH hardening
/// (spec §10.3, RF-18).
///
/// The 32-byte seed is the only secret; the 32-byte public key is derived
/// from it. The seed lives in [seedBytes] in memory and is the value the
/// caller is responsible for persisting to secure storage.
///
/// This wrapper never logs or stringifies the seed: [toString] reveals only
/// the public key.
@immutable
class Ed25519KeyPair {
  /// Creates an [Ed25519KeyPair] from already-known bytes.
  ///
  /// [seedBytes] must be exactly 32 bytes; [publicKeyBytes] must be exactly
  /// 32 bytes derived from the same seed (no consistency check is performed
  /// here — use [fromSeed] or [generate] when the caller cannot prove that).
  Ed25519KeyPair({
    required Uint8List seedBytes,
    required Uint8List publicKeyBytes,
  }) : assert(
         seedBytes.length == 32,
         'Ed25519 seed must be 32 bytes',
       ),
       assert(
         publicKeyBytes.length == 32,
         'Ed25519 public key must be 32 bytes',
       ),
       seedBytes = Uint8List.fromList(seedBytes),
       publicKeyBytes = Uint8List.fromList(publicKeyBytes);

  /// Generates a fresh Ed25519 key pair via the `cryptography` package
  /// (spec §14).
  static Future<Ed25519KeyPair> generate() async {
    final keyPair = await crypto.Ed25519().newKeyPair();
    final seed = await keyPair.extractPrivateKeyBytes();
    final publicKey = await keyPair.extractPublicKey();
    return Ed25519KeyPair(
      seedBytes: Uint8List.fromList(seed),
      publicKeyBytes: Uint8List.fromList(publicKey.bytes),
    );
  }

  /// Reconstructs an Ed25519 key pair from a known 32-byte seed.
  static Future<Ed25519KeyPair> fromSeed(Uint8List seed) async {
    if (seed.length != 32) {
      throw ArgumentError('Ed25519 seed must be 32 bytes');
    }
    final keyPair = await crypto.Ed25519().newKeyPairFromSeed(seed);
    final publicKey = await keyPair.extractPublicKey();
    return Ed25519KeyPair(
      seedBytes: seed,
      publicKeyBytes: Uint8List.fromList(publicKey.bytes),
    );
  }

  /// The 32-byte seed — the only secret of the pair.
  final Uint8List seedBytes;

  /// The 32-byte Ed25519 public key.
  final Uint8List publicKeyBytes;

  /// The 64-byte expanded private key used by libsodium (seed || pubkey).
  ///
  /// This is the form `dartssh2`'s `OpenSSHEd25519KeyPair` expects (it feeds
  /// it directly into `pinenacl.SigningKey.fromValidBytes`).
  Uint8List get expandedPrivateKey {
    final out = Uint8List(64)
      ..setRange(0, 32, seedBytes)
      ..setRange(32, 64, publicKeyBytes);
    return out;
  }

  /// Renders the public key as a single OpenSSH `authorized_keys` line:
  /// `ssh-ed25519 BASE64(SSH-encoded-key) <comment>`.
  ///
  /// [comment] must not contain whitespace — typical form is
  /// `fav@<device-or-server-id>`.
  String authorizedKeysEntry({required String comment}) {
    if (RegExp(r'\s').hasMatch(comment)) {
      throw ArgumentError('comment must not contain whitespace');
    }
    return 'ssh-ed25519 ${_sshWireFormatBase64()} $comment';
  }

  /// Builds a `dartssh2` key pair usable as an `identities` entry on
  /// `SSHClient`.
  ssh.OpenSSHEd25519KeyPair asDartSshKeyPair({required String comment}) {
    return ssh.OpenSSHEd25519KeyPair(
      publicKeyBytes,
      expandedPrivateKey,
      comment,
    );
  }

  /// Encodes the public key in the SSH wire format used in `authorized_keys`:
  /// `string("ssh-ed25519") || string(32-byte pubkey)`, base64-encoded.
  String _sshWireFormatBase64() {
    const algorithm = 'ssh-ed25519';
    final algoBytes = utf8.encode(algorithm);
    final blob = BytesBuilder()
      ..add(_uint32BigEndian(algoBytes.length))
      ..add(algoBytes)
      ..add(_uint32BigEndian(publicKeyBytes.length))
      ..add(publicKeyBytes);
    return base64.encode(blob.toBytes());
  }

  static Uint8List _uint32BigEndian(int value) {
    final out = Uint8List(4);
    out.buffer.asByteData().setUint32(0, value);
    return out;
  }

  @override
  String toString() => 'Ed25519KeyPair(public: <32 bytes>, seed: <redacted>)';
}
