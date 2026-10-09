import 'dart:convert';
import 'dart:typed_data';

import 'package:fav/core/errors/app_exception.dart';
import 'package:fav/features/install/data/scripts/asset_script_repository.dart';
import 'package:fav/features/install/data/scripts/editable_script_catalog.dart';
import 'package:fav/features/install/data/scripts/hive_user_script_repository.dart';
import 'package:fav/features/install/data/scripts/script_integrity.dart';
import 'package:fav/features/install/domain/script_source.dart';
import 'package:fav/features/install/domain/user_script_repository.dart';
import 'package:fav/features/peers/data/peer_script_source.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Resolves the *effective* content of every script: the user's editable
/// override when one exists, otherwise the immutable bundled original.
///
/// Overrides are stored in the encrypted `scripts` box keyed by relative path
/// (see [kEditableScriptPaths]) and are layered AFTER boot integrity
/// verification — the `bundle` passed here is the pristine, verified set, so a
/// tampered override can never corrupt the trusted baseline used for diff and
/// restore (spec §8.6).
class EffectiveScriptResolver {
  /// Creates a resolver over the verified `bundle`, the [_peerSource] (for the
  /// peer scripts that live outside the bundle) and the override [_overrides].
  EffectiveScriptResolver({
    required this._bundle,
    required this._peerSource,
    required this._overrides,
  });

  final ScriptBundle _bundle;
  final PeerScriptSource _peerSource;
  final UserScriptRepository _overrides;

  /// The pristine, integrity-verified installer bundle (no overrides applied).
  ScriptBundle get pristineBundle => _bundle;

  /// Returns the immutable original (bundled) bytes for [relativePath].
  ///
  /// Peer paths are sourced from [PeerScriptSource]; every other path from the
  /// verified installer `bundle`. Throws [AppException] (`scriptInvalid`) for a
  /// path that is neither.
  Future<Uint8List> originalBytesFor(String relativePath) async {
    if (isPeerScriptPath(relativePath)) {
      final scripts = await _peerSource.load();
      switch (relativePath) {
        case kPeerAddScript:
          return scripts.add.bytes;
        case kPeerRevokeScript:
          return scripts.revoke.bytes;
      }
    }
    for (final asset in _bundle.assets) {
      if (asset.relativePath == relativePath) {
        return asset.bytes;
      }
    }
    throw const AppException(
      ErrorCode.scriptInvalid,
      detail: 'unknown script path',
    );
  }

  /// Returns the effective bytes for [relativePath]: the override when present,
  /// otherwise [originalBytesFor].
  Future<Uint8List> bytesFor(String relativePath) async {
    final override = await _overrides.getById(relativePath);
    if (override != null) {
      return Uint8List.fromList(utf8.encode(override.content));
    }
    return originalBytesFor(relativePath);
  }

  /// Returns the installer `bundle` with every overridden asset's bytes
  /// substituted, and the canonical [ScriptBundle.bundleHash] recomputed over
  /// the effective set.
  ///
  /// Only covers paths present in the installer bundle (peer scripts are
  /// uploaded by their own runners and are not part of a [ScriptBundle]).
  Future<ScriptBundle> effectiveBundle() async {
    final overridesById = await _loadOverrides();
    if (overridesById.isEmpty) {
      return _bundle;
    }
    final assets = [
      for (final asset in _bundle.assets)
        if (overridesById.containsKey(asset.relativePath))
          ScriptAsset(
            relativePath: asset.relativePath,
            bytes: Uint8List.fromList(
              utf8.encode(overridesById[asset.relativePath]!),
            ),
          )
        else
          asset,
    ]..sort((a, b) => a.relativePath.compareTo(b.relativePath));
    return ScriptBundle(
      assets: assets,
      bundleHash: canonicalBundleHash(assets),
    );
  }

  /// Whether the user has at least one override for a known catalog path.
  Future<bool> hasAnyOverride() async {
    final overridesById = await _loadOverrides();
    return overridesById.isNotEmpty;
  }

  /// Deletes any override row whose key is not a current catalog path.
  ///
  /// Pre-release builds stored orchestrator overrides under a random UUID
  /// (`AdvancedOptions.customScriptId`). Those keys never match a path, so
  /// they would otherwise linger forever and make [hasAnyOverride] spuriously
  /// true. Best-effort: a delete failure is not fatal.
  Future<void> pruneUnknownOverrides() async {
    const known = {...kEditableScriptPaths};
    final all = await _overrides.getAll();
    for (final script in all) {
      if (!known.contains(script.id)) {
        await _overrides.delete(script.id);
      }
    }
  }

  /// Loads all overrides keyed by path, filtered to known catalog paths so a
  /// stale UUID-keyed row can never be counted or applied.
  Future<Map<String, String>> _loadOverrides() async {
    const known = {...kEditableScriptPaths};
    final all = await _overrides.getAll();
    return {
      for (final script in all)
        if (known.contains(script.id)) script.id: script.content,
    };
  }
}

/// Provides an [EffectiveScriptResolver] over the integrity-verified bundle.
///
/// Prunes stale (non-catalog) override rows once on construction.
final FutureProvider<EffectiveScriptResolver> effectiveScriptResolverProvider =
    FutureProvider<EffectiveScriptResolver>((ref) async {
      final bundle = await ref.watch(bootIntegrityProvider.future);
      final resolver = EffectiveScriptResolver(
        bundle: bundle,
        peerSource: ref.watch(peerScriptSourceProvider),
        overrides: ref.watch(userScriptRepositoryProvider),
      );
      await resolver.pruneUnknownOverrides();
      return resolver;
    });
