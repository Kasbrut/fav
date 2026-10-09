import 'package:fav/core/errors/app_exception.dart';
import 'package:fav/features/install/application/ssh_auth_resolver.dart';
import 'package:fav/features/install/data/ssh/dart_ssh_client.dart';
import 'package:fav/features/install/domain/ssh_client.dart';
import 'package:fav/features/monitoring/data/events_jsonl_parser.dart';
import 'package:fav/features/monitoring/data/peers_state_parser.dart';
import 'package:fav/features/monitoring/domain/monitor_repository.dart';
import 'package:fav/features/monitoring/domain/peer_event.dart';
import 'package:fav/features/monitoring/domain/peer_snapshot.dart';
import 'package:fav/features/servers/domain/server.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Path of the snapshot JSON file produced by the agent.
const String kMonitorSnapshotPath = '/var/lib/fav/peers-state.json';

/// Path of the events log produced by the agent.
const String kMonitorEventsPath = '/var/log/fav/events.jsonl';

/// Sentinel separating the snapshot and events content in a single ssh `run`
/// so we keep the round-trip count to one per polling tick.
const String _streamSentinel = '\n---WG-MONITOR-SEP---\n';

/// First line of the events payload. The device/inode identifies rotation and
/// the line count is the high-water mark for the current (unrotated) file.
const String _eventsCursorMarker = 'WG-EVT-CURSOR';

final RegExp _eventsCursorPattern = RegExp(
  r'^WG-EVT-CURSOR ((?:[0-9]+:[0-9]+)|missing) ([0-9]+)$',
);
final RegExp _eventsFileIdPattern = RegExp(
  r'^(?:[0-9]+:[0-9]+|missing)$',
);

/// SSH-backed [MonitorRepository] that reads the agent's files via `cat`
/// over a key-authenticated SSH session (M15-T5).
class SshMonitorRepository implements MonitorRepository {
  /// Creates an [SshMonitorRepository].
  const SshMonitorRepository({
    required this.clientFactory,
    required this.authResolver,
    this.snapshotParser = const PeersStateParser(),
    this.eventsParser = const EventsJsonlParser(),
  });

  /// Factory that builds a fresh [SshClient] per call.
  final SshClient Function() clientFactory;

  /// Resolver picking key-auth when the server carries an `sshKeyId`.
  final SshAuthResolver authResolver;

  /// Snapshot JSON parser.
  final PeersStateParser snapshotParser;

  /// Events JSONL parser.
  final EventsJsonlParser eventsParser;

  @override
  Future<PeersStateSnapshot?> fetchSnapshot(Server server) async {
    final result = await fetchAll(server);
    return result.snapshot;
  }

  @override
  Future<List<PeerEvent>> fetchEvents(Server server) async {
    final result = await fetchAll(server);
    return result.events;
  }

  /// Fetches the snapshot and the events log in a single SSH session.
  /// Throws [AppException] when SSH itself fails; returns an empty result
  /// when the agent is not installed (missing files).
  ///
  /// [eventsLineOffset] and [eventsFileId] form the caller's cursor. While the
  /// current log keeps the same device/inode, only unseen lines are downloaded
  /// (audit M13). On the first read or after logrotate, the seven retained
  /// archives are streamed oldest-first before the current file so events
  /// created while the app was unreachable are recovered. The encrypted local
  /// box deduplicates events already imported.
  Future<MonitorReadResult> fetchAll(
    Server server, {
    int eventsLineOffset = 0,
    String? eventsFileId,
  }) async {
    final client = clientFactory();
    try {
      await client.connect(await authResolver.resolve(server: server));
      // One round trip: the snapshot `cat` and the events tail joined by a
      // sentinel. Trailing `|| true` keeps the command zero-exit even when
      // the agent is not installed (files missing) — the caller
      // distinguishes by the parsed payload.
      final expectedFileId =
          eventsFileId != null && _eventsFileIdPattern.hasMatch(eventsFileId)
          ? eventsFileId
          : '';
      const shellDollar = r'$';
      final command =
          "(cat '$kMonitorSnapshotPath' 2>/dev/null; echo; "
          "echo -n '${_streamSentinel.trim()}'; echo; "
          "LN=$shellDollar(wc -l < '$kMonitorEventsPath' 2>/dev/null || echo 0); "
          "FID=$shellDollar(stat -c '%d:%i' '$kMonitorEventsPath' 2>/dev/null || "
          "echo missing); echo '$_eventsCursorMarker '\"${shellDollar}FID\" "
          '"${shellDollar}LN"; '
          "if [ '$expectedFileId' != \"${shellDollar}FID\" ] || "
          '[ "${shellDollar}LN" -lt $eventsLineOffset ]; then '
          'for N in 7 6 5 4 3 2 1; do '
          "P='$kMonitorEventsPath'.${shellDollar}N; "
          'if [ -f "${shellDollar}P.gz" ]; then '
          'gzip -cd -- "${shellDollar}P.gz"; '
          'elif [ -f "${shellDollar}P" ]; then '
          'cat -- "${shellDollar}P"; fi; done; '
          "cat '$kMonitorEventsPath' 2>/dev/null; "
          'else tail -n +${eventsLineOffset + 1} '
          "'$kMonitorEventsPath' 2>/dev/null; fi) || true";
      final output = (await client.run(command)).stdout;
      final parts = output.split(_streamSentinel);
      final snapshotRaw = parts.isNotEmpty ? parts.first : '';
      var eventsRaw = parts.length > 1 ? parts.sublist(1).join() : '';
      var nextFileId = expectedFileId.isEmpty ? null : expectedFileId;
      int? nextLineOffset;
      final firstNewline = eventsRaw.indexOf('\n');
      final cursorLine = firstNewline < 0
          ? eventsRaw
          : eventsRaw.substring(0, firstNewline);
      final cursor = _eventsCursorPattern.firstMatch(cursorLine.trim());
      if (cursor != null) {
        nextFileId = cursor.group(1);
        nextLineOffset = int.parse(cursor.group(2)!);
        eventsRaw = firstNewline < 0
            ? ''
            : eventsRaw.substring(firstNewline + 1);
      }
      final snapshot = snapshotParser.tryParse(snapshotRaw);
      final events = eventsParser.parse(
        serverId: server.id,
        content: eventsRaw,
      );
      return MonitorReadResult(
        snapshot: snapshot,
        events: events,
        nextEventsLineOffset:
            nextLineOffset ??
            eventsLineOffset + '\n'.allMatches(eventsRaw).length,
        nextEventsFileId: nextFileId,
      );
    } finally {
      await client.close();
    }
  }
}

/// A single read of the monitor agent's state (M15-T5).
class MonitorReadResult {
  /// Creates a [MonitorReadResult].
  const MonitorReadResult({
    required this.snapshot,
    required this.events,
    this.nextEventsLineOffset = 0,
    this.nextEventsFileId,
  });

  /// Parsed snapshot, or `null` when the agent is not installed / unreachable.
  final PeersStateSnapshot? snapshot;

  /// Events parsed from the agent's log. May be empty.
  final List<PeerEvent> events;

  /// High-water mark to pass as `eventsLineOffset` on the next tick: the
  /// number of complete events lines consumed so far (audit M13).
  final int nextEventsLineOffset;

  /// Device/inode identity of the current events file, or `missing`.
  final String? nextEventsFileId;
}

/// Provides the SSH-backed [MonitorRepository].
final Provider<MonitorRepository> monitorRepositoryProvider =
    Provider<MonitorRepository>(
      (ref) => SshMonitorRepository(
        clientFactory: ref.watch(sshClientFactoryProvider),
        authResolver: ref.watch(sshAuthResolverProvider),
      ),
    );
