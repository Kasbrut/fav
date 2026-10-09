import 'package:fav/features/peers/data/peer_script_source.dart';
import 'package:flutter/services.dart';

/// Tiny [AssetBundle] backing [PeerScriptSource] in tests: returns the
/// supplied bytes for both peer assets. The exact content doesn't matter
/// for runner tests — only the shape of the SSH calls is asserted.
class FakePeerAssetBundle extends CachingAssetBundle {
  /// Creates a [FakePeerAssetBundle] using [addBytes] for `peer_add.sh` and
  /// [revokeBytes] for `peer_revoke.sh`.
  FakePeerAssetBundle({
    Uint8List? addBytes,
    Uint8List? revokeBytes,
    Uint8List? rendererBytes,
    Uint8List? managerBytes,
  }) : _addBytes = addBytes ?? Uint8List.fromList([0x41]),
       _revokeBytes = revokeBytes ?? Uint8List.fromList([0x52]),
       _rendererBytes = rendererBytes ?? Uint8List.fromList([0x50]),
       _managerBytes = managerBytes ?? Uint8List.fromList([0x4d]);

  final Uint8List _addBytes;
  final Uint8List _revokeBytes;
  final Uint8List _rendererBytes;
  final Uint8List _managerBytes;

  @override
  Future<ByteData> load(String key) async {
    if (key == PeerScriptSource.addAssetPath) {
      return ByteData.view(
        _addBytes.buffer,
        _addBytes.offsetInBytes,
        _addBytes.lengthInBytes,
      );
    }
    if (key == PeerScriptSource.revokeAssetPath) {
      return ByteData.view(
        _revokeBytes.buffer,
        _revokeBytes.offsetInBytes,
        _revokeBytes.lengthInBytes,
      );
    }
    if (key == PeerScriptSource.rendererAssetPath) {
      return ByteData.view(
        _rendererBytes.buffer,
        _rendererBytes.offsetInBytes,
        _rendererBytes.lengthInBytes,
      );
    }
    if (key == PeerScriptSource.managerAssetPath) {
      return ByteData.view(
        _managerBytes.buffer,
        _managerBytes.offsetInBytes,
        _managerBytes.lengthInBytes,
      );
    }
    throw Exception('unexpected asset key: $key');
  }
}
