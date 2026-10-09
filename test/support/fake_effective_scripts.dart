import 'dart:convert';
import 'dart:typed_data';

import 'package:fav/features/install/data/scripts/asset_script_repository.dart';
import 'package:fav/features/install/data/scripts/effective_script_resolver.dart';
import 'package:fav/features/install/domain/script_source.dart';
import 'package:fav/features/install/domain/user_script_repository.dart';
import 'package:fav/features/peers/data/peer_script_source.dart';

import 'peer_script_bundle.dart';

/// Builds a fake installer [ScriptBundle] covering every manifest path, with
/// each file's content set to `# <path>`.
ScriptBundle fakeInstallerBundle() {
  final assets = [
    for (final path in kScriptManifest)
      ScriptAsset(
        relativePath: path,
        bytes: Uint8List.fromList(utf8.encode('# $path\n')),
      ),
  ]..sort((a, b) => a.relativePath.compareTo(b.relativePath));
  return ScriptBundle(assets: assets, bundleHash: canonicalBundleHash(assets));
}

/// Builds an [EffectiveScriptResolver] over the fake installer bundle, a fake
/// peer source and the given [overrides] repository.
EffectiveScriptResolver fakeResolver(UserScriptRepository overrides) {
  return EffectiveScriptResolver(
    bundle: fakeInstallerBundle(),
    peerSource: PeerScriptSource(
      bundle: FakePeerAssetBundle(
        addBytes: Uint8List.fromList(utf8.encode('# peers/peer_add.sh\n')),
        revokeBytes: Uint8List.fromList(
          utf8.encode('# peers/peer_revoke.sh\n'),
        ),
      ),
      expectedHashes: const {},
    ),
    overrides: overrides,
  );
}
