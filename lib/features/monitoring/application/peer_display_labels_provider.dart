import 'package:fav/features/peers/application/peers_controller.dart';
import 'package:fav/features/peers/domain/peer.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';

/// Maps each peer's public key to the user-defined label for the given server.
///
/// Returns an empty map while the peers controller is loading or errored —
/// callers fall back to the short-pubkey display in that case, then
/// live-update when peers resolve.
final ProviderFamily<Map<String, String>, String> peerDisplayLabelsProvider =
    Provider.autoDispose.family<Map<String, String>, String>((ref, serverId) {
      final peers = ref.watch(peersControllerProvider(serverId));
      return peers.maybeWhen<Map<String, String>>(
        data: (list) => <String, String>{
          for (final Peer p in list) p.publicKey: p.label,
        },
        orElse: () => const <String, String>{},
      );
    });

/// Display string for [publicKey].
///
/// Returns the matching label from [labels] when present and non-empty.
/// Otherwise returns the short pubkey: the full key when its length is
/// `<= 12`, the first 8 characters followed by an ellipsis otherwise.
String peerDisplayLabel(String publicKey, Map<String, String> labels) {
  final label = labels[publicKey];
  if (label != null && label.isNotEmpty) {
    return label;
  }
  if (publicKey.length <= 12) {
    return publicKey;
  }
  return '${publicKey.substring(0, 8)}…';
}

/// Whether the value rendered by [peerDisplayLabel] for [publicKey] is the
/// short-pubkey fallback (true) or a real label (false).
bool isPubkeyFallback(String publicKey, Map<String, String> labels) {
  final label = labels[publicKey];
  return label == null || label.isEmpty;
}

/// Returns [peers] reordered for display.
///
/// Peers with a non-empty label come first, sorted by label
/// case-insensitively. Peers without a label come after, sorted by raw
/// public key as a stable tie-breaker.
List<String> sortPeersByDisplay(
  Iterable<String> peers,
  Map<String, String> labels,
) {
  final list = peers.toList()
    ..sort((a, b) {
      final la = labels[a];
      final lb = labels[b];
      final aHas = la != null && la.isNotEmpty;
      final bHas = lb != null && lb.isNotEmpty;
      if (aHas && !bHas) return -1;
      if (!aHas && bHas) return 1;
      if (aHas && bHas) {
        final cmp = la.toLowerCase().compareTo(lb.toLowerCase());
        if (cmp != 0) return cmp;
      }
      return a.compareTo(b);
    });
  return list;
}
