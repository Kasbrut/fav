import 'dart:typed_data';

import 'package:fav/core/crypto/sha256_hasher.dart';
import 'package:fav/core/errors/app_exception.dart';
import 'package:flutter/services.dart' show AssetBundle, rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Expected SHA-256 (lowercase hex) of the bundled peer scripts, keyed by
/// asset path. Compiled into the app so a repackaged/tampered peer script —
/// which is generated with root privileges on the server — is rejected before
/// use, closing the §8.6 gap the install bundle already covers (audit
/// M-peer-integrity). Kept honest by peer_script_source_test, which recomputes
/// them from the real assets.
const Map<String, String> kPeerScriptHashes = {
  'lib/assets/scripts/lib/profile_renderer.py':
      'c64d9e5c5087321da9dd7055806a84302ce5fc33b6b0df692f33ea9932bd46db',
  'lib/assets/scripts/lib/peer_manager.py':
      'f4279d7b24ed9b637de3bcb6dee639594ccd80eb6d304041e1647adda9b3613e',
  'lib/assets/scripts/peers/peer_add.sh':
      '1c415f176f15b373b88571352034fa207272980efd2337fd6fd2f9b93a008a19',
  'lib/assets/scripts/peers/peer_revoke.sh':
      '022e1096b846f41b30a725341329a7a3b7e3d04ccfbbad057655ca0f3dcaaafd',
};

/// One peer-management script bundled with the app, with its SHA-256 hash
/// used for the on-server filename.
class PeerScriptAsset {
  /// Creates a [PeerScriptAsset].
  PeerScriptAsset({required this.bytes, required this.sha256Hex});

  /// Raw bytes of the bundled script.
  final Uint8List bytes;

  /// Lowercase hex SHA-256 digest of [bytes].
  final String sha256Hex;

  /// First 16 hex characters of [sha256Hex] — short enough for a filename
  /// component, long enough to avoid collisions for the two scripts we ship.
  String get shortHash => sha256Hex.substring(0, 16);
}

/// The bundled multi-peer scripts loaded from Flutter assets.
class PeerScripts {
  /// Creates a [PeerScripts] bundle.
  PeerScripts({
    required this.add,
    required this.revoke,
    required this.renderer,
    required this.manager,
  });

  /// `peer_add.sh` asset.
  final PeerScriptAsset add;

  /// `peer_revoke.sh` asset.
  final PeerScriptAsset revoke;

  /// Shared v2 profile renderer, uploaded by future T6 peer operations.
  final PeerScriptAsset renderer;

  /// Transactional manifest-authoritative v2 peer manager.
  final PeerScriptAsset manager;
}

/// Loads the bundled multi-peer scripts and computes their hashes.
///
/// Bundled assets are immutable for a given app build, so this can be
/// memoised; a single instance per app run is enough.
class PeerScriptSource {
  /// Creates a [PeerScriptSource] reading from [bundle].
  ///
  /// [bundle] defaults to [rootBundle]; tests pass a fake asset bundle.
  /// [expectedHashes] defaults to [kPeerScriptHashes]; tests using a fake
  /// bundle pass `const {}` to skip the integrity check.
  PeerScriptSource({AssetBundle? bundle, Map<String, String>? expectedHashes})
    : _bundle = bundle ?? rootBundle,
      _expectedHashes = expectedHashes ?? kPeerScriptHashes;

  final AssetBundle _bundle;
  final Map<String, String> _expectedHashes;
  PeerScripts? _cached;

  /// Bundled-asset path of the `peer_add.sh` script.
  static const String addAssetPath = 'lib/assets/scripts/peers/peer_add.sh';

  /// Bundled-asset path of the `peer_revoke.sh` script.
  static const String revokeAssetPath =
      'lib/assets/scripts/peers/peer_revoke.sh';

  /// Bundled-asset path of the shared v2 profile renderer.
  static const String rendererAssetPath =
      'lib/assets/scripts/lib/profile_renderer.py';

  /// Bundled-asset path of the v2 peer manager.
  static const String managerAssetPath =
      'lib/assets/scripts/lib/peer_manager.py';

  /// Loads (or returns the cached copy of) the bundled scripts.
  Future<PeerScripts> load() async {
    final cached = _cached;
    if (cached != null) {
      return cached;
    }
    final addBytes = await _load(addAssetPath);
    final revokeBytes = await _load(revokeAssetPath);
    final rendererBytes = await _load(rendererAssetPath);
    final managerBytes = await _load(managerAssetPath);
    final addHash = sha256Hex(addBytes);
    final revokeHash = sha256Hex(revokeBytes);
    final rendererHash = sha256Hex(rendererBytes);
    final managerHash = sha256Hex(managerBytes);
    _verify(addAssetPath, addHash);
    _verify(revokeAssetPath, revokeHash);
    _verify(rendererAssetPath, rendererHash);
    _verify(managerAssetPath, managerHash);
    final scripts = PeerScripts(
      add: PeerScriptAsset(bytes: addBytes, sha256Hex: addHash),
      revoke: PeerScriptAsset(bytes: revokeBytes, sha256Hex: revokeHash),
      renderer: PeerScriptAsset(bytes: rendererBytes, sha256Hex: rendererHash),
      manager: PeerScriptAsset(bytes: managerBytes, sha256Hex: managerHash),
    );
    _cached = scripts;
    return scripts;
  }

  /// Throws [AppException] ([ErrorCode.scriptInvalid], fail-closed) when the
  /// bundled script at [path] does not match its compiled-in hash. Paths not
  /// present in [_expectedHashes] are not checked (test fakes pass `const {}`).
  void _verify(String path, String actualHash) {
    final expected = _expectedHashes[path];
    if (expected != null && expected != actualHash) {
      throw const AppException(
        ErrorCode.scriptInvalid,
        detail: 'peer script integrity check failed',
      );
    }
  }

  Future<Uint8List> _load(String path) async {
    final data = await _bundle.load(path);
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }
}

/// Provides a single, app-wide [PeerScriptSource].
final Provider<PeerScriptSource> peerScriptSourceProvider =
    Provider<PeerScriptSource>((ref) => PeerScriptSource());
