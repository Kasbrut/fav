import 'dart:convert';

import 'package:fav/features/monitoring/domain/peer_event.dart';

/// Parses the agent's `events.jsonl` log into a list of [PeerEvent]s
/// (M15-T5). One JSON object per line; the last line may be incomplete
/// (truncated by a concurrent write) and is skipped.
class EventsJsonlParser {
  /// Creates an [EventsJsonlParser].
  const EventsJsonlParser();

  /// Parses [content] for [serverId], returning every event whose JSON line
  /// is well-formed. Lines with unknown event types are kept (mapped to
  /// `disconnect` as a conservative default). Lines that cannot be parsed
  /// at all are silently dropped.
  List<PeerEvent> parse({required String serverId, required String content}) {
    if (content.trim().isEmpty) {
      return const <PeerEvent>[];
    }
    final events = <PeerEvent>[];
    for (final raw in const LineSplitter().convert(content)) {
      final line = raw.trim();
      if (line.isEmpty) {
        continue;
      }
      final dynamic decoded;
      try {
        decoded = jsonDecode(line);
      } on FormatException {
        // Last line may be partial during a rotate window — skip silently.
        continue;
      }
      if (decoded is! Map<String, dynamic>) {
        continue;
      }
      final pubkey = decoded['publicKey'];
      final typeName = decoded['type'];
      final tsRaw = decoded['serverTimestamp'];
      if (pubkey is! String || typeName is! String || tsRaw is! String) {
        continue;
      }
      final timestamp = DateTime.tryParse(tsRaw);
      if (timestamp == null) {
        continue;
      }
      final type = PeerEventType.values.firstWhere(
        (value) => value.name == typeName,
        orElse: () => PeerEventType.disconnect,
      );
      events.add(
        PeerEvent(
          serverId: serverId,
          peerPublicKey: pubkey,
          type: type,
          serverTimestamp: timestamp,
          rx: (decoded['rx'] as num?)?.toInt() ?? 0,
          tx: (decoded['tx'] as num?)?.toInt() ?? 0,
          latestHandshake: (decoded['latestHandshake'] as num?)?.toInt() ?? 0,
        ),
      );
    }
    return events;
  }
}
