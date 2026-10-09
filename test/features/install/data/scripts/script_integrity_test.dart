import 'dart:convert';
import 'dart:io';

import 'package:fav/core/crypto/sha256_hasher.dart';
import 'package:fav/core/errors/app_exception.dart';
import 'package:fav/features/install/data/scripts/asset_script_repository.dart';
import 'package:fav/features/install/data/scripts/script_integrity.dart';
import 'package:fav/features/install/domain/script_source.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Asset bundle backed by an in-memory map, for integrity tests.
class _MapAssetBundle extends CachingAssetBundle {
  _MapAssetBundle(this._files);

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
  Map<String, Uint8List> realAssetFiles() {
    return {
      for (final relativePath in kScriptManifest)
        'lib/assets/scripts/$relativePath': File(
          'lib/assets/scripts/$relativePath',
        ).readAsBytesSync(),
    };
  }

  test('kBundledScriptHashes matches the real asset files (§8.6)', () {
    final computed = <String, String>{};
    final assets = <ScriptAsset>[];
    for (final relativePath in kScriptManifest) {
      final bytes = File(
        'lib/assets/scripts/$relativePath',
      ).readAsBytesSync();
      computed[relativePath] = sha256Hex(bytes);
      assets.add(ScriptAsset(relativePath: relativePath, bytes: bytes));
    }
    final setHash = canonicalBundleHash(assets);
    printOnFailure('Recomputed kBundledScriptHashes:\n$computed');
    printOnFailure('Recomputed kBundledScriptSetHash:\n$setHash');
    expect(
      computed,
      kBundledScriptHashes,
      reason: 'installer scripts changed — refresh the integrity constants',
    );
    expect(
      setHash,
      kBundledScriptSetHash,
      reason: 'installer scripts changed — refresh the integrity constants',
    );
  });

  test('verifyAndLoad accepts the untampered bundle', () async {
    final verifier = ScriptIntegrityVerifier(
      AssetScriptRepository(bundle: _MapAssetBundle(realAssetFiles())),
    );
    final bundle = await verifier.verifyAndLoad();
    expect(bundle.assets, hasLength(kScriptManifest.length));
    expect(bundle.bundleHash, kBundledScriptSetHash);
  });

  test('verifyAndLoad rejects a tampered script (fail-closed)', () async {
    final files = realAssetFiles()
      ..['lib/assets/scripts/modules/00_probe.sh'] = Uint8List.fromList(
        utf8.encode('# tampered'),
      );
    final verifier = ScriptIntegrityVerifier(
      AssetScriptRepository(bundle: _MapAssetBundle(files)),
    );
    await expectLater(
      verifier.verifyAndLoad(),
      throwsA(
        isA<AppException>().having(
          (e) => e.code,
          'code',
          ErrorCode.scriptInvalid,
        ),
      ),
    );
  });
}
