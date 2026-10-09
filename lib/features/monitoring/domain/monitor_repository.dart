import 'package:fav/features/monitoring/domain/peer_event.dart';
import 'package:fav/features/monitoring/domain/peer_snapshot.dart';
import 'package:fav/features/servers/domain/server.dart';

/// Reads the live peer state and recent events from the server agent
/// (M15-T5). Implementations: SSH-based (`SshMonitorRepository`).
abstract interface class MonitorRepository {
  /// Fetches the latest snapshot from the agent's `peers-state.json`.
  ///
  /// Returns `null` when the snapshot file does not exist (agent not
  /// installed on the server).
  Future<PeersStateSnapshot?> fetchSnapshot(Server server);

  /// Fetches events from `events.jsonl`. Returns them ordered by
  /// `serverTimestamp` ascending.
  Future<List<PeerEvent>> fetchEvents(Server server);
}
