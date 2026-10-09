import 'package:fav/core/errors/app_exception.dart';
import 'package:fav/features/profile/data/client_profile_parser.dart';
import 'package:fav/features/servers/domain/wireguard_installation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const parser = ClientProfileParser();

  // 32-byte all-zero key (base64). X25519 accepts it as a seed (it gets
  // clamped internally) — enough for the parser test, which exercises the
  // text format, not the cryptographic content.
  const validPrivateKey = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=';

  const validConf =
      '''
[Interface]
PrivateKey = $validPrivateKey
Address = 10.13.13.2/32
DNS = 1.1.1.1, 1.0.0.1
MTU = 1420

[Peer]
PublicKey = aSERVERPUBLICKEY/0123456789abcdefghijklmnopqrs=
PresharedKey = aPSK/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa=
Endpoint = vpn.example.com:51820
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
''';

  test('parses every standard wg-quick field', () async {
    final profile = await parser.parse(validConf);
    expect(profile.privateKey, validPrivateKey);
    // The derived public key must be a 44-char standard-base64 string.
    expect(profile.clientPublicKey, hasLength(44));
    expect(profile.clientPublicKey.endsWith('='), isTrue);
    expect(profile.address, '10.13.13.2/32');
    expect(profile.dns, ['1.1.1.1', '1.0.0.1']);
    expect(profile.mtu, 1420);
    expect(profile.serverPublicKey, startsWith('aSERVERPUBLICKEY'));
    expect(profile.presharedKey, startsWith('aPSK'));
    expect(profile.endpoint, 'vpn.example.com:51820');
    expect(profile.allowedIps, ['0.0.0.0/0']);
    expect(profile.persistentKeepalive, 25);
  });

  test('tolerates lowercase headers and extra whitespace', () async {
    const messy =
        '''
   [interface]
   privatekey   =   $validPrivateKey
   address=10.0.0.2/32
   dns = 9.9.9.9
   mtu=1280
[peer]
publickey =  serverpub
endpoint =     host:1234
allowedips =   10.0.0.0/8 ,  172.16.0.0/12
''';
    final profile = await parser.parse(messy);
    expect(profile.privateKey, validPrivateKey);
    expect(profile.address, '10.0.0.2/32');
    expect(profile.dns, ['9.9.9.9']);
    expect(profile.mtu, 1280);
    expect(profile.serverPublicKey, 'serverpub');
    expect(profile.allowedIps, ['10.0.0.0/8', '172.16.0.0/12']);
    expect(profile.presharedKey, isNull);
    expect(profile.persistentKeepalive, isNull);
  });

  test('strips inline comments', () async {
    const conf =
        '''
[Interface]
PrivateKey = $validPrivateKey  # not the real key in a comment
Address = 10.0.0.2/32  # tunnel address
DNS = 1.1.1.1
MTU = 1420
[Peer]
PublicKey = serverpub
Endpoint = host:51820
AllowedIPs = 0.0.0.0/0
''';
    final profile = await parser.parse(conf);
    expect(profile.privateKey, validPrivateKey);
    expect(profile.address, '10.0.0.2/32');
  });

  test('throws ERR-SCRIPT-01 when a required field is missing', () async {
    const missingEndpoint =
        '''
[Interface]
PrivateKey = $validPrivateKey
Address = 10.0.0.2/32
DNS = 1.1.1.1
MTU = 1420
[Peer]
PublicKey = serverpub
AllowedIPs = 0.0.0.0/0
''';
    await expectLater(
      parser.parse(missingEndpoint),
      throwsA(
        isA<AppException>().having(
          (error) => error.code,
          'code',
          ErrorCode.scriptInvalid,
        ),
      ),
    );
  });

  test('throws ERR-SCRIPT-01 when MTU is not an integer', () async {
    const bad =
        '''
[Interface]
PrivateKey = $validPrivateKey
Address = 10.0.0.2/32
DNS = 1.1.1.1
MTU = oops
[Peer]
PublicKey = serverpub
Endpoint = host:51820
AllowedIPs = 0.0.0.0/0
''';
    await expectLater(parser.parse(bad), throwsA(isA<AppException>()));
  });

  test(
    'throws ERR-SCRIPT-01 when the private key is not valid base64 32 bytes',
    () async {
      const conf = '''
[Interface]
PrivateKey = not-a-valid-key
Address = 10.0.0.2/32
DNS = 1.1.1.1
MTU = 1420
[Peer]
PublicKey = serverpub
Endpoint = host:51820
AllowedIPs = 0.0.0.0/0
''';
      await expectLater(
        parser.parse(conf),
        throwsA(
          isA<AppException>().having(
            (error) => error.code,
            'code',
            ErrorCode.scriptInvalid,
          ),
        ),
      );
    },
  );

  test('ignores unknown sections (forward compatible)', () async {
    const conf =
        '''
[Interface]
PrivateKey = $validPrivateKey
Address = 10.0.0.2/32
DNS = 1.1.1.1
MTU = 1420
[Peer]
PublicKey = serverpub
Endpoint = host:51820
AllowedIPs = 0.0.0.0/0
[Unknown]
FutureField = whatever
''';
    await parser.parse(conf);
  });

  test(
    'parses comma-separated and repeated dual-stack Address entries',
    () async {
      for (final addressLines in [
        'Address = 10.13.13.2/32, fd12:3456:789a::2/128',
        'Address = 10.13.13.2/32\nAddress = fd12:3456:789a::2/128',
      ]) {
        final profile = await parser.parse('''
[Interface]
PrivateKey = $validPrivateKey
$addressLines
DNS = 1.1.1.1
MTU = 1420
[Peer]
PublicKey = serverpub
Endpoint = host:51820
AllowedIPs = 0.0.0.0/0, ::/0
''');
        expect(profile.ipv4Address, '10.13.13.2/32');
        expect(profile.ipv6Address, 'fd12:3456:789a::2/128');
      }
    },
  );

  test('rejects conflicting or duplicate address families', () async {
    const conf =
        '''
[Interface]
PrivateKey = $validPrivateKey
Address = 10.13.13.2/32, 10.13.13.3/32
DNS = 1.1.1.1
MTU = 1420
[Peer]
PublicKey = serverpub
Endpoint = host:51820
AllowedIPs = 0.0.0.0/0
''';
    await expectLater(parser.parse(conf), throwsA(isA<AppException>()));
  });

  test(
    'strict v2 requires valid keys, addresses and both default routes',
    () async {
      const validKey = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=';
      const conf =
          '''
[Interface]
PrivateKey = $validPrivateKey
Address = 10.13.13.2/32
Address = fd12:3456:789a::2/128
DNS = 1.1.1.1
MTU = 1420
[Peer]
PublicKey = $validKey
PresharedKey = $validKey
Endpoint = host:51820
AllowedIPs = 0.0.0.0/0, ::/0
''';
      final profile = await parser.parse(
        conf,
        requireV2: true,
        ipv6Mode: Ipv6Mode.blocked,
      );
      expect(profile.version, 2);

      await expectLater(
        parser.parse(
          conf.replaceFirst(', ::/0', ''),
          requireV2: true,
          ipv6Mode: Ipv6Mode.blocked,
        ),
        throwsA(isA<AppException>()),
      );
    },
  );
}
