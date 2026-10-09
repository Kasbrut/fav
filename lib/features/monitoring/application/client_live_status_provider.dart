import 'package:fav/features/monitoring/application/monitor_polling_controller.dart';
import 'package:fav/features/monitoring/data/monitor_events_box.dart';
import 'package:fav/features/monitoring/domain/client_live_status.dart';
import 'package:fav/features/monitoring/domain/peer_event.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:meta/meta.dart';

/// Arguments for [clientLiveStatusProvider]: `(serverId, peerPublicKey)`.
@immutable
class ClientLiveStatusKey {
  /// Creates a [ClientLiveStatusKey].
  const ClientLiveStatusKey({
    required this.serverId,
    required this.peerPublicKey,
  });

  /// Identifier of the server the peer belongs to.
  final String serverId;

  /// Canonical-base64 public key of the peer.
  final String peerPublicKey;

  @override
  bool operator ==(Object other) =>
      other is ClientLiveStatusKey &&
      other.serverId == serverId &&
      other.peerPublicKey == peerPublicKey;

  @override
  int get hashCode => Object.hash(serverId, peerPublicKey);
}

/// Derives the live status of a single peer (M15-T5) from the polling
/// state and the local events box.
///
/// Mapping rules (in order):
///   - SSH down / `notInstalled` error → `Unknown(reason)`
///   - No snapshot yet → `Unknown(sshDown)` (best effort: no info yet)
///   - Snapshot older than `agentStale` threshold → `Unknown(agentStale)`
///   - Peer present and `online=true` → `Connected`
///   - Peer present but offline → `LastSeen(handshake)` when handshake>0,
///     else fall back to the most recent local event for the peer; else
///     `NeverConnected`
///   - Peer absent from snapshot → `NeverConnected`
final ProviderFamily<ClientLiveStatus, ClientLiveStatusKey>
clientLiveStatusProvider = Provider.autoDispose
    .family<ClientLiveStatus, ClientLiveStatusKey>((ref, key) {
      final polling = ref.watch(
        monitorPollingControllerProvider(key.serverId),
      );

      // Surface transient transport errors as the matching Unknown case.
      if (polling.lastErrorReason != null && polling.snapshot == null) {
        return ClientLiveStatusUnknown(polling.lastErrorReason!);
      }

      final snapshot = polling.snapshot;
      if (snapshot == null) {
        return const ClientLiveStatusUnknown(
          ClientLiveStatusUnknownReason.sshDown,
        );
      }
      final age = DateTime.now().toUtc().difference(snapshot.generatedAt);
      if (age > kMonitorAgentStaleThreshold) {
        return const ClientLiveStatusUnknown(
          ClientLiveStatusUnknownReason.agentStale,
        );
      }

      final matches = snapshot.peers.where(
        (p) => p.publicKey == key.peerPublicKey,
      );
      if (matches.isEmpty) {
        return const ClientLiveStatusNeverConnected();
      }
      final peer = matches.first;
      if (peer.online) {
        return const ClientLiveStatusConnected();
      }
      if (peer.latestHandshake > 0) {
        return ClientLiveStatusLastSeen(
          DateTime.fromMillisecondsSinceEpoch(
            peer.latestHandshake * 1000,
            isUtc: true,
          ),
        );
      }

      // Fall back to the most recent local event for the peer — useful when
      // the handshake counter resets after a server restart.
      final events = ref
          .watch(monitorEventsBoxProvider)
          .getForServer(key.serverId)
          .where((event) => event.peerPublicKey == key.peerPublicKey);
      DateTime? lastSeen;
      for (final event in events) {
        if (event.type == PeerEventType.connect) {
          if (lastSeen == null || event.serverTimestamp.isAfter(lastSeen)) {
            lastSeen = event.serverTimestamp;
          }
        }
      }
      if (lastSeen != null) {
        return ClientLiveStatusLastSeen(lastSeen);
      }
      return const ClientLiveStatusNeverConnected();
    });
