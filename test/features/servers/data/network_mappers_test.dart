import 'package:fav/features/install/data/run_mappers.dart';
import 'package:fav/features/install/domain/advanced_options.dart';
import 'package:fav/features/install/domain/install_run.dart';
import 'package:fav/features/peers/data/peer_mappers.dart';
import 'package:fav/features/peers/domain/peer.dart';
import 'package:fav/features/servers/data/network_mappers.dart';
import 'package:fav/features/servers/domain/network_configuration_validator.dart';
import 'package:fav/features/servers/domain/wireguard_installation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final valid = <String, Object?>{
    'schemaVersion': 2,
    'installationId': 'i',
    'revision': 1,
    'ipv6Mode': 'blocked',
    'ipv4Subnet': '10.0.0.0/24',
    'ipv6Subnet': 'fd00::/64',
    'fallbackIpv6Subnet': 'fd00::/64',
    'serverIpv6Address': 'fd00::1/64',
    'capabilityStatus': 'unknown',
    'capabilityReason': 'none',
    'capabilityCheckedAt': '2026-09-17T00:00:00Z',
  };
  test('legacy absent metadata is legacy', () {
    expect(
      networkConfigurationFromMap({}).status,
      NetworkMetadataStatus.legacy,
    );
  });
  test('valid v2 round trips', () {
    final n = networkConfigurationFromMap(valid);
    expect(n.isStructurallyValidV2, isTrue);
    expect(networkConfigurationFromMap(networkConfigurationToMap(n)), n);
  });
  test('partial, wrong-type and malformed v2 stay invalid', () {
    expect(
      networkConfigurationFromMap({'schemaVersion': 2}).status,
      NetworkMetadataStatus.invalid,
    );
    expect(
      networkConfigurationFromMap({'schemaVersion': '2'}).status,
      NetworkMetadataStatus.invalid,
    );
    expect(
      networkConfigurationFromMap({
        ...valid,
        'capabilityCheckedAt': 'bad',
      }).status,
      NetworkMetadataStatus.invalid,
    );
  });
  test('future version stays unsupported', () {
    final raw = {...valid, 'schemaVersion': 3, 'futureField': 'keep-me'};
    final parsed = networkConfigurationFromMap(raw);
    expect(parsed.status, NetworkMetadataStatus.unsupported);
    expect(networkConfigurationToMap(parsed), raw);
  });
  test('malformed containers and versions never round trip as legacy', () {
    for (final raw in [
      42,
      'bad',
      {'schemaVersion': '2'},
      {'schemaVersion': 2},
    ]) {
      final value = networkConfigurationFromMap(raw);
      expect(value.status, NetworkMetadataStatus.invalid);
      expect(
        networkConfigurationFromMap(networkConfigurationToMap(value)).status,
        NetworkMetadataStatus.invalid,
      );
    }
    final legacy = networkConfigurationFromMap({});
    expect(
      networkConfigurationFromMap(networkConfigurationToMap(legacy)),
      legacy,
    );
    for (final patch in [
      {'revision': 0},
      {'ipv6Mode': 'legacy'},
      {'installationId': ''},
      {'ipv6Subnet': 42},
      {'capabilityCheckedAt': 42},
    ]) {
      expect(
        networkConfigurationFromMap({...valid, ...patch}).status,
        NetworkMetadataStatus.invalid,
      );
    }
  });
  test('peer IPv6 persists without changing the legacy IPv4 identity', () {
    final peer = Peer(
      id: 'p',
      serverId: 's',
      label: 'phone',
      address: '10.0.0.2/32',
      publicKey: 'key',
      createdAt: DateTime.utc(2026),
    );
    expect(peerFromMap(peerToMap(peer)), peer);
    final dual = peer.copyWith(ipv6Address: 'fd00::2/128');
    expect(dual.ipv4Address, peer.address);
    expect(dual, isNot(peer));
    expect(peerFromMap(peerToMap(dual)), dual);
    expect(dual.copyWith(label: 'renamed').ipv6Address, dual.ipv6Address);
  });
  test('run persists network and requested delegated prefix', () {
    final network = networkConfigurationFromMap(valid);
    final run = InstallRun(
      runId: 'r',
      serverId: 's',
      status: RunStatus.running,
      steps: const [],
      scriptWasModified: false,
      startedAt: DateTime.utc(2026),
      network: network,
      options: const AdvancedOptions(delegatedIpv6Prefix: '2001:4860::/64'),
    );
    expect(runFromMap(runToMap(run)), run);
    expect(run.copyWith(status: RunStatus.success).network, network);
    final malformed = runToMap(run)..['network'] = 'not a map';
    expect(
      runFromMap(malformed).network?.status,
      NetworkMetadataStatus.invalid,
    );
    expect(run.copyWith(clearNetwork: true).network, isNull);
  });

  test('semantic v2 validation checks subnets, mode and UTC evidence', () {
    expect(
      networkConfigurationV2Problem(networkConfigurationFromMap(valid)),
      isNull,
    );

    for (final patch in [
      {'ipv4Subnet': '10.0.0.0/16'},
      {'ipv6Subnet': 'fd00:0:0:0::/64'},
      {'serverIpv6Address': 'fd00::2/64'},
      {'capabilityCheckedAt': '2026-09-17T00:00:00'},
      {'capabilityStatus': 'supported'},
      {'installationId': 'bad identity'},
      {'capabilityReason': 'bad reason'},
    ]) {
      expect(
        networkConfigurationV2Problem(
          networkConfigurationFromMap({...valid, ...patch}),
        ),
        isNotNull,
        reason: '$patch',
      );
    }

    final routed = networkConfigurationFromMap({
      ...valid,
      'ipv6Mode': 'routed',
      'ipv6Subnet': '2001:4860:1234::/64',
      'serverIpv6Address': '2001:4860:1234::1/64',
      'capabilityStatus': 'supported',
    });
    expect(networkConfigurationV2Problem(routed), isNull);
  });

  test('copyWith can explicitly clear nullable migration fields', () {
    final network = networkConfigurationFromMap(valid);
    final installation = WireguardInstallation(
      interfaceName: 'wg0',
      listenPort: 51820,
      vpnSubnet: '10.0.0.0/24',
      serverPublicKey: 'key',
      peers: const [],
      hardeningApplied: false,
      installedAt: DateTime.utc(2026),
      network: network,
    );
    expect(installation.copyWith(clearNetwork: true).network, isNull);
    final peer = Peer(
      id: 'p',
      serverId: 's',
      label: 'phone',
      address: '10.0.0.2/32',
      ipv6Address: 'fd00::2/128',
      publicKey: 'key',
      createdAt: DateTime.utc(2026),
    );
    expect(peer.copyWith(clearIpv6Address: true).ipv6Address, isNull);
  });
}
