import 'dart:async';

import 'package:fav/core/errors/app_exception.dart';
import 'package:fav/features/profile/application/client_profile_provider.dart';
import 'package:fav/features/profile/data/secure_client_profile_repository.dart';
import 'package:fav/features/profile/domain/client_profile_repository.dart';
import 'package:fav/features/servers/data/hive_server_repository.dart';
import 'package:fav/features/servers/domain/wireguard_installation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/server_fakes.dart';

class _Profiles implements ClientProfileRepository {
  _Profiles(this.raw);

  String? raw;

  @override
  Future<void> delete(String serverId) async => raw = null;

  @override
  Future<String?> getRaw(String serverId) async => raw;

  @override
  Future<void> save({required String serverId, required String rawConf}) async {
    raw = rawConf;
  }
}

void main() {
  test(
    'invalid and future v2 metadata block profile export before parsing',
    () async {
      for (final network in [
        const NetworkConfiguration(
          schemaVersion: 2,
          status: NetworkMetadataStatus.invalid,
        ),
        const NetworkConfiguration(
          schemaVersion: 3,
          status: NetworkMetadataStatus.unsupported,
        ),
      ]) {
        final servers = FakeServerRepository();
        await servers.save(
          testServer().copyWith(
            installation: WireguardInstallation(
              interfaceName: 'wg0',
              listenPort: 51820,
              vpnSubnet: '10.13.13.0/24',
              serverPublicKey: 'key',
              peers: const [],
              hardeningApplied: false,
              installedAt: DateTime.utc(2026),
              network: network,
            ),
          ),
        );
        final container = ProviderContainer(
          overrides: [
            serverRepositoryProvider.overrideWithValue(servers),
            clientProfileRepositoryProvider.overrideWithValue(
              _Profiles('corrupt profile that must not be exported'),
            ),
          ],
        );
        addTearDown(container.dispose);
        final error = Completer<Object>();
        final subscription = container.listen(
          clientProfileProvider('srv-1'),
          (_, next) {
            if (next.hasError && !error.isCompleted) {
              error.complete(next.error!);
            }
          },
          fireImmediately: true,
        );
        addTearDown(subscription.close);

        expect(
          await error.future,
          isA<AppException>().having(
            (error) => error.code,
            'code',
            ErrorCode.scriptInvalid,
          ),
        );
      }
    },
  );

  test('valid matching v2 metadata releases a dual-stack profile', () async {
    const key = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=';
    const raw =
        '''
[Interface]
PrivateKey = $key
Address = 10.13.13.2/32, fd12:3456:789a::2/128
DNS = 1.1.1.1
MTU = 1420
[Peer]
PublicKey = $key
PresharedKey = $key
Endpoint = vpn.example.org:51820
AllowedIPs = 0.0.0.0/0, ::/0
''';
    final servers = FakeServerRepository();
    await servers.save(
      testServer().copyWith(
        installation: WireguardInstallation(
          interfaceName: 'wg0',
          listenPort: 51820,
          vpnSubnet: '10.13.13.0/24',
          serverPublicKey: key,
          peers: const [],
          hardeningApplied: false,
          installedAt: DateTime.utc(2026),
          network: NetworkConfiguration(
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
          ),
        ),
      ),
    );
    final container = ProviderContainer(
      overrides: [
        serverRepositoryProvider.overrideWithValue(servers),
        clientProfileRepositoryProvider.overrideWithValue(_Profiles(raw)),
      ],
    );
    addTearDown(container.dispose);
    final subscription = container.listen(
      clientProfileProvider('srv-1'),
      (_, _) {},
    );
    addTearDown(subscription.close);

    final bundle = await container.read(clientProfileProvider('srv-1').future);
    expect(bundle?.profile.version, 2);
    expect(bundle?.profile.ipv6Address, 'fd12:3456:789a::2/128');
  });
}
