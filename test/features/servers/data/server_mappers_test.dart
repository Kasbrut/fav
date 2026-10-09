// The SSH key fixture is a single unsplittable base64 token.
// ignore_for_file: lines_longer_than_80_chars

import 'package:fav/features/servers/data/server_mappers.dart';
import 'package:fav/features/servers/domain/server.dart';
import 'package:fav/features/servers/domain/server_metadata.dart';
import 'package:fav/features/servers/domain/wireguard_installation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tests for the server storage mappers.
void main() {
  test('round-trip preserves every field of a fully populated server', () {
    final server = Server(
      id: 'id-1',
      label: 'vps-amsterdam',
      host: '203.0.113.5',
      sshPort: 22,
      username: 'root',
      sshKeyId: 'key-1',
      createdAt: DateTime(2026, 5, 18, 10, 30),
      lastSeenAt: DateTime(2026, 5, 18, 12),
      metadata: ServerMetadata(
        osId: 'debian',
        osVersion: '12 (bookworm)',
        prettyName: 'Debian GNU/Linux 12 (bookworm)',
        kernelVersion: '6.1.0-13-amd64',
        architecture: 'x86_64',
        hostname: 'vps',
        totalMemoryMb: 2048,
        cpuCount: 2,
        publicIp: '203.0.113.5',
        networkInterfaces: const ['eth0', 'wg0'],
        probedAt: DateTime(2026, 5, 18, 10, 35),
      ),
      installation: WireguardInstallation(
        interfaceName: 'wg0',
        listenPort: 51820,
        vpnSubnet: '10.13.13.0/24',
        serverPublicKey: 'pubkey',
        peers: const [
          PeerSummary(publicKey: 'p1', allowedIp: '10.13.13.2/32'),
        ],
        hardeningApplied: true,
        rootSshDisabled: true,
        portReachability: WireguardPortReachability.blocked,
        portCheckedAt: DateTime(2026, 5, 18, 11, 1),
        publicEndpoint: 'vpn.example.com',
        installedAt: DateTime(2026, 5, 18, 11),
      ),
      userAuthorizedKeys: const [
        'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILumuaB4RSmE61UE6zVVVutcGA5HoayYq1PhFhdkFg9e user@laptop',
        'ssh-rsa AAAAB3NzaC1yc2E= desktop',
      ],
    );

    expect(serverFromMap(serverToMap(server)), equals(server));
  });

  test('rootSshDisabled defaults to false for legacy installations', () {
    // Records written before the field shipped must read as "root SSH not
    // disabled" so the teardown modal stays conservative but functional.
    final legacy = <String, Object?>{
      'id': 'id-4',
      'label': 'legacy',
      'host': 'host.example.com',
      'sshPort': 22,
      'username': 'root',
      'createdAt': DateTime(2026).toIso8601String(),
      'installation': <String, Object?>{
        'interfaceName': 'wg0',
        'listenPort': 51820,
        'vpnSubnet': '10.13.13.0/24',
        'serverPublicKey': 'pub',
        'peers': <Object?>[],
        'hardeningApplied': false,
        'installedAt': DateTime(2026).toIso8601String(),
      },
    };

    expect(serverFromMap(legacy).installation!.rootSshDisabled, isFalse);
    expect(
      serverFromMap(legacy).installation!.portReachability,
      WireguardPortReachability.unknown,
    );
  });

  test('userAuthorizedKeys defaults to empty for legacy records', () {
    // A record written before the feature shipped has no such key.
    final legacy = <String, Object?>{
      'id': 'id-3',
      'label': 'legacy',
      'host': 'host.example.com',
      'sshPort': 22,
      'username': 'root',
      'createdAt': DateTime(2026).toIso8601String(),
    };

    expect(serverFromMap(legacy).userAuthorizedKeys, isEmpty);
  });

  test('round-trip works for a minimal server', () {
    final server = Server(
      id: 'id-2',
      label: 'minimal',
      host: 'host.example.com',
      sshPort: 2222,
      username: 'deploy',
      createdAt: DateTime(2026, 5, 18),
    );

    expect(serverFromMap(serverToMap(server)), equals(server));
  });
}
