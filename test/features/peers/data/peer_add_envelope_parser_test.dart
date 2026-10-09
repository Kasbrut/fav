import 'package:fav/core/errors/app_exception.dart';
import 'package:fav/core/wireguard/wg_public_key.dart';
import 'package:fav/features/peers/data/peer_add_envelope_parser.dart';
import 'package:fav/features/servers/domain/wireguard_installation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const parser = PeerAddEnvelopeParser();

  const wellFormed = '''
ADDR=10.13.13.3/32
PUBKEY=AAA=
---BEGIN-CONF---
[Interface]
PrivateKey = BBB
Address = 10.13.13.3/32
DNS = 1.1.1.1

[Peer]
PublicKey = CCC
PresharedKey = DDD
Endpoint = vpn.example.org:51820
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
---END-CONF---
''';

  group('PeerAddEnvelopeParser', () {
    test('parses a well-formed envelope', () async {
      final envelope = await parser.parse(wellFormed);
      expect(envelope.address, '10.13.13.3/32');
      expect(envelope.publicKey, 'AAA=');
      expect(envelope.rawConf, startsWith('[Interface]\n'));
      expect(envelope.rawConf, contains('PrivateKey = BBB'));
      expect(envelope.rawConf, contains('PersistentKeepalive = 25'));
      expect(envelope.rawConf, endsWith('\n'));
    });

    test('tolerates log lines and banners before ADDR=', () async {
      const noisy = '''
Welcome to Ubuntu 22.04 LTS
Last login: yesterday
[2026-05-26T20:00:00Z] peer_add ready
ADDR=10.13.13.3/32
PUBKEY=AAA=
---BEGIN-CONF---
[Interface]
PrivateKey = BBB
---END-CONF---
''';
      final envelope = await parser.parse(noisy);
      expect(envelope.address, '10.13.13.3/32');
      expect(envelope.rawConf, '[Interface]\nPrivateKey = BBB\n');
    });

    test('ignores trailing output after ---END-CONF---', () async {
      const trailing = '''
ADDR=10.13.13.3/32
PUBKEY=AAA=
---BEGIN-CONF---
[Interface]
PrivateKey = BBB
---END-CONF---
Connection to host closed.
some other junk
''';
      final envelope = await parser.parse(trailing);
      expect(envelope.rawConf, '[Interface]\nPrivateKey = BBB\n');
    });

    test('normalises CRLF line endings to LF', () async {
      final crlf = wellFormed.replaceAll('\n', '\r\n');
      final envelope = await parser.parse(crlf);
      expect(envelope.address, '10.13.13.3/32');
      expect(envelope.rawConf, isNot(contains('\r')));
    });

    test('throws peerParseFailed when ADDR is missing', () async {
      const noAddr = '''
PUBKEY=AAA=
---BEGIN-CONF---
[Interface]
---END-CONF---
''';
      await expectLater(
        parser.parse(noAddr),
        throwsA(
          predicate(
            (e) => e is AppException && e.code == ErrorCode.peerParseFailed,
          ),
        ),
      );
    });

    test('throws peerParseFailed when PUBKEY is missing', () async {
      const noPub = '''
ADDR=10.13.13.3/32
---BEGIN-CONF---
[Interface]
---END-CONF---
''';
      await expectLater(
        parser.parse(noPub),
        throwsA(
          predicate(
            (e) => e is AppException && e.code == ErrorCode.peerParseFailed,
          ),
        ),
      );
    });

    test(
      'throws peerParseFailed when the body close marker is absent',
      () async {
        const noEnd = '''
ADDR=10.13.13.3/32
PUBKEY=AAA=
---BEGIN-CONF---
[Interface]
PrivateKey = BBB
''';
        await expectLater(
          parser.parse(noEnd),
          throwsA(
            predicate(
              (e) => e is AppException && e.code == ErrorCode.peerParseFailed,
            ),
          ),
        );
      },
    );

    test('throws peerParseFailed on completely unrelated output', () async {
      const garbage = 'sudo: no tty present and no askpass program specified\n';
      await expectLater(
        parser.parse(garbage),
        throwsA(
          predicate(
            (e) => e is AppException && e.code == ErrorCode.peerParseFailed,
          ),
        ),
      );
    });

    test('parses and cross-checks a valid v2 envelope', () async {
      final output = await _v2Envelope();
      final envelope = await parser.parse(output, expected: _expectation);
      expect(envelope.version, 2);
      expect(envelope.installationId, 'installation-1');
      expect(envelope.operationId, 'operation-1');
      expect(envelope.revision, 2);
      expect(envelope.ipv6Mode, Ipv6Mode.blocked);
      expect(envelope.address, '10.13.13.2/32');
      expect(envelope.ipv6Address, 'fd12:3456:789a::2/128');
    });

    test('rejects future, partial and duplicate v2 headers as v2', () async {
      final valid = await _v2Envelope();
      for (final output in [
        valid.replaceFirst('FAV_ENVELOPE_VERSION=2', 'FAV_ENVELOPE_VERSION=3'),
        valid.replaceFirst('INSTALLATION_ID=installation-1\n', ''),
        valid.replaceFirst(
          'REVISION=2',
          'REVISION=2\nREVISION=2',
        ),
      ]) {
        await expectLater(
          parser.parse(output, expected: _expectation),
          throwsA(
            isA<AppException>().having(
              (error) => error.code,
              'code',
              ErrorCode.peerParseFailed,
            ),
          ),
        );
      }
    });

    test('rejects v2 profile/header and full-tunnel mismatches', () async {
      final valid = await _v2Envelope();
      for (final output in [
        valid.replaceFirst('ADDR4=10.13.13.2/32', 'ADDR4=10.13.13.3/32'),
        valid.replaceFirst(
          'AllowedIPs = 0.0.0.0/0, ::/0',
          'AllowedIPs = 0.0.0.0/0',
        ),
        valid.replaceFirst(
          'OPERATION_ID=operation-1',
          'OPERATION_ID=operation-2',
        ),
      ]) {
        await expectLater(
          parser.parse(output, expected: _expectation),
          throwsA(isA<AppException>()),
        );
      }
    });
  });
}

final _network = NetworkConfiguration(
  schemaVersion: 2,
  installationId: 'installation-1',
  revision: 1,
  ipv6Mode: Ipv6Mode.blocked,
  ipv4Subnet: '10.13.13.0/24',
  ipv6Subnet: 'fd12:3456:789a::/64',
  fallbackIpv6Subnet: 'fd12:3456:789a::/64',
  serverIpv6Address: 'fd12:3456:789a::1/64',
  capabilityStatus: CapabilityStatus.unknown,
  capabilityReason: 'no_delegated_prefix',
  capabilityCheckedAt: DateTime.utc(2026, 9, 17),
  status: NetworkMetadataStatus.valid,
);

final _expectation = PeerAddEnvelopeExpectation(
  network: _network,
  operationId: 'operation-1',
  revision: 2,
);

Future<String> _v2Envelope() async {
  const privateKey = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=';
  final publicKey = await WgPublicKey.fromPrivateKey(privateKey);
  return '''
Welcome banner
FAV_ENVELOPE_VERSION=2
INSTALLATION_ID=installation-1
OPERATION_ID=operation-1
REVISION=2
IPV6_MODE=blocked
ADDR4=10.13.13.2/32
ADDR6=fd12:3456:789a::2/128
PUBKEY=${publicKey.canonical}
---BEGIN-CONF---
[Interface]
PrivateKey = $privateKey
Address = 10.13.13.2/32, fd12:3456:789a::2/128
DNS = 1.1.1.1
MTU = 1420

[Peer]
PublicKey = $privateKey
PresharedKey = $privateKey
Endpoint = vpn.example.org:51820
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
---END-CONF---
''';
}
