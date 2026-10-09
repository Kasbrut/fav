import 'dart:typed_data';

import 'package:meta/meta.dart';

/// One bundled installer script file with its raw content.
@immutable
class ScriptAsset {
  /// Creates a [ScriptAsset].
  const ScriptAsset({required this.relativePath, required this.bytes});

  /// Path relative to the bundled script root, with POSIX separators
  /// (for example `install_wireguard.sh` or `modules/00_probe.sh`).
  final String relativePath;

  /// Raw file content.
  final Uint8List bytes;
}

/// The complete set of installer scripts plus a hash over the whole set.
@immutable
class ScriptBundle {
  /// Creates a [ScriptBundle].
  const ScriptBundle({required this.assets, required this.bundleHash});

  /// Bundled scripts, sorted by [ScriptAsset.relativePath].
  final List<ScriptAsset> assets;

  /// Lowercase hex SHA-256 over the canonical digest of the whole set.
  final String bundleHash;
}
