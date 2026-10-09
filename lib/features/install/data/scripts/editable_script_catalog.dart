import 'package:fav/features/install/data/scripts/asset_script_repository.dart';
import 'package:fav/features/peers/data/peer_script_source.dart';

/// Relative paths of the peer-management scripts, expressed against the same
/// script root as [kScriptManifest] (e.g. `peers/peer_add.sh`).
///
/// They are bundled but live OUTSIDE the integrity-verified set
/// (`kBundledScriptHashes`) and are loaded by [PeerScriptSource], not the
/// installer bundle. They are unioned in here only so the script editor can
/// show and override them like every other file.
const String kPeerAddScript = 'peers/peer_add.sh';

/// Relative path of the peer-revoke script (see [kPeerAddScript]).
const String kPeerRevokeScript = 'peers/peer_revoke.sh';

/// Every script/file the user may view and override, in display order.
///
/// This is the full installer bundle ([kScriptManifest]) plus the two peer
/// scripts. The override store (`UserScriptRepository`) is keyed by these
/// paths; an absent override means the effective content is the bundled
/// original (see `EffectiveScriptResolver`).
const List<String> kEditableScriptPaths = [
  ...kScriptManifest,
  kPeerAddScript,
  kPeerRevokeScript,
];

/// Whether [relativePath] is a peer script loaded via [PeerScriptSource]
/// rather than the installer asset bundle.
bool isPeerScriptPath(String relativePath) => relativePath.startsWith('peers/');

/// Maps a peer relative path to the full asset path used by
/// [PeerScriptSource]; returns `null` for non-peer paths.
String? peerAssetPathFor(String relativePath) {
  switch (relativePath) {
    case kPeerAddScript:
      return PeerScriptSource.addAssetPath;
    case kPeerRevokeScript:
      return PeerScriptSource.revokeAssetPath;
    default:
      return null;
  }
}

/// Display group of a script, used to organise the editor's file picker.
enum ScriptGroup {
  /// The orchestrator, shared library and numbered installer modules.
  installer,

  /// The standalone hardening / anti-lockout scripts.
  hardening,

  /// The peer-monitoring agent bundle.
  monitoring,

  /// The peer add/revoke scripts.
  peers,
}

/// Classifies [relativePath] into its [ScriptGroup] for the picker.
ScriptGroup scriptGroupFor(String relativePath) {
  if (isPeerScriptPath(relativePath)) {
    return ScriptGroup.peers;
  }
  if (relativePath == kAntiLockoutScript ||
      relativePath == kDisablePasswordAuthScript) {
    return ScriptGroup.hardening;
  }
  if (relativePath.contains('monitor')) {
    return ScriptGroup.monitoring;
  }
  return ScriptGroup.installer;
}
