import 'package:fav/features/monitoring/data/peers_state_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const parser = PeersStateParser();

  test('parses a well-formed snapshot', () {
    const content = '''
{
  "schemaVersion": 1,
  "monitorVersion": "1.0.0",
  "generatedAt": "2026-05-22T10:00:00Z",
  "interface": {"publicKey": "srv_pub", "listenPort": 51820},
  "peers": [
    {
      "publicKey": "peer1",
      "endpoint": "1.2.3.4:51820",
      "allowedIps": ["10.13.13.2/32"],
      "latestHandshake": 1747900000,
      "rx": 1024,
      "tx": 2048,
      "online": true
    }
  ]
}
''';
    final snap = parser.tryParse(content)!;
    expect(snap.monitorVersion, '1.0.0');
    expect(snap.interfacePublicKey, 'srv_pub');
    expect(snap.interfaceListenPort, 51820);
    expect(snap.peers, hasLength(1));
    expect(snap.peers.first.publicKey, 'peer1');
    expect(snap.peers.first.online, isTrue);
    expect(snap.peers.first.endpointInMemory, '1.2.3.4:51820');
    expect(snap.peers.first.allowedIps, ['10.13.13.2/32']);
    expect(snap.peers.first.rx, 1024);
    expect(snap.peers.first.tx, 2048);
  });

  test('returns null when schemaVersion is not 1', () {
    const content =
        '{"schemaVersion": 2, "generatedAt": '
        '"2026-05-22T10:00:00Z", "peers": []}';
    expect(parser.tryParse(content), isNull);
  });

  test('returns null when generatedAt is missing', () {
    const content = '{"schemaVersion": 1, "peers": []}';
    expect(parser.tryParse(content), isNull);
  });

  test('returns null for empty input', () {
    expect(parser.tryParse(''), isNull);
    expect(parser.tryParse('   '), isNull);
  });

  test('returns null for malformed JSON', () {
    expect(parser.tryParse('{not json'), isNull);
  });

  test(
    'skips peer entries that are malformed without dropping the snapshot',
    () {
      const content = '''
{
  "schemaVersion": 1,
  "generatedAt": "2026-05-22T10:00:00Z",
  "interface": null,
  "peers": [
    {"publicKey": "good", "online": false},
    {"endpoint": "no-pubkey"},
    "not-a-map"
  ]
}
''';
      final snap = parser.tryParse(content)!;
      expect(snap.peers, hasLength(1));
      expect(snap.peers.first.publicKey, 'good');
    },
  );
}
