import 'package:fav/features/monitoring/data/events_jsonl_parser.dart';
import 'package:fav/features/monitoring/domain/peer_event.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const parser = EventsJsonlParser();

  test('parses every valid line and assigns the serverId', () {
    const jsonl = '''
{"serverTimestamp":"2026-05-22T09:00:00Z","publicKey":"peer1","type":"connect","rx":10,"tx":20,"latestHandshake":1747900000}
{"serverTimestamp":"2026-05-22T09:05:00Z","publicKey":"peer1","type":"disconnect","rx":50,"tx":80,"latestHandshake":1747900100}
''';
    final events = parser.parse(serverId: 'srv-1', content: jsonl);
    expect(events, hasLength(2));
    expect(events.first.serverId, 'srv-1');
    expect(events.first.type, PeerEventType.connect);
    expect(events.last.type, PeerEventType.disconnect);
    expect(events.last.rx, 50);
  });

  test('drops malformed lines without aborting the parse', () {
    const jsonl = '''
{"serverTimestamp":"2026-05-22T09:00:00Z","publicKey":"peer1","type":"connect","rx":10,"tx":20,"latestHandshake":0}
{not json
{"serverTimestamp":"2026-05-22T09:06:00Z","publicKey":"peer2","type":"connect","rx":1,"tx":2,"latestHandshake":1}
''';
    final events = parser.parse(serverId: 's', content: jsonl);
    expect(events, hasLength(2));
    expect(events.first.peerPublicKey, 'peer1');
    expect(events.last.peerPublicKey, 'peer2');
  });

  test('returns an empty list for empty input', () {
    expect(parser.parse(serverId: 's', content: ''), isEmpty);
    expect(parser.parse(serverId: 's', content: '\n\n'), isEmpty);
  });

  test('an unknown type falls back to disconnect (conservative default)', () {
    const jsonl =
        '{"serverTimestamp":"2026-05-22T09:00:00Z","publicKey":"peer1",'
        '"type":"frobnicate","rx":0,"tx":0,"latestHandshake":0}';
    final events = parser.parse(serverId: 's', content: jsonl);
    expect(events.single.type, PeerEventType.disconnect);
  });
}
