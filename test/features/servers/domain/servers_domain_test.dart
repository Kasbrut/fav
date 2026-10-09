import 'package:fav/features/servers/domain/host_key_fingerprint.dart';
import 'package:fav/features/servers/domain/server.dart';
import 'package:fav/features/servers/domain/server_metadata.dart';
import 'package:fav/features/servers/domain/wireguard_installation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tests for the servers-feature domain entities.
void main() {
  ServerMetadata buildMetadata() => ServerMetadata(
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
    probedAt: DateTime(2026, 5, 18),
  );

  HostKeyFingerprint buildFingerprint() => HostKeyFingerprint(
    host: '203.0.113.5',
    port: 22,
    keyType: 'ssh-ed25519',
    hashAlgorithm: 'md5',
    fingerprint: 'aa:bb:cc',
    pinnedAt: DateTime(2026, 5, 18),
  );

  WireguardInstallation buildInstallation() => WireguardInstallation(
    interfaceName: 'wg0',
    listenPort: 51820,
    vpnSubnet: '10.13.13.0/24',
    serverPublicKey: 'pubkey',
    peers: const [PeerSummary(publicKey: 'p', allowedIp: '10.13.13.2/32')],
    hardeningApplied: false,
    installedAt: DateTime(2026, 5, 18),
  );

  Server buildServer() => Server(
    id: 'id-1',
    label: 'vps-amsterdam',
    host: '203.0.113.5',
    sshPort: 22,
    username: 'root',
    createdAt: DateTime(2026, 5, 18),
  );

  group('ServerMetadata', () {
    test('equality and hashCode', () {
      expect(buildMetadata(), equals(buildMetadata()));
      expect(buildMetadata().hashCode, equals(buildMetadata().hashCode));
    });

    test('list field participates in equality', () {
      final shorter = buildMetadata().copyWith(
        networkInterfaces: const ['eth0'],
      );
      expect(buildMetadata(), isNot(equals(shorter)));
    });

    test('copyWith replaces only the given field', () {
      final updated = buildMetadata().copyWith(cpuCount: 8);
      expect(updated.cpuCount, 8);
      expect(updated.osId, 'debian');
    });
  });

  group('HostKeyFingerprint', () {
    test('equality, hashCode and copyWith', () {
      expect(buildFingerprint(), equals(buildFingerprint()));
      expect(
        buildFingerprint().hashCode,
        equals(buildFingerprint().hashCode),
      );
      final changed = buildFingerprint().copyWith(fingerprint: 'dd:ee:ff');
      expect(buildFingerprint(), isNot(equals(changed)));
    });
  });

  group('WireguardInstallation', () {
    test('equality with the peers list', () {
      expect(buildInstallation(), equals(buildInstallation()));
      expect(
        buildInstallation().hashCode,
        equals(buildInstallation().hashCode),
      );
      final noPeers = buildInstallation().copyWith(peers: const []);
      expect(buildInstallation(), isNot(equals(noPeers)));
    });

    test('copyWith updates the listen port', () {
      expect(buildInstallation().copyWith(listenPort: 51821).listenPort, 51821);
    });
  });

  group('PeerSummary', () {
    test('equality, hashCode and copyWith', () {
      const a = PeerSummary(publicKey: 'p', allowedIp: '10.13.13.2/32');
      const b = PeerSummary(publicKey: 'p', allowedIp: '10.13.13.2/32');
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a.copyWith(label: 'phone').label, 'phone');
    });
  });

  group('Server', () {
    test('equality, hashCode and copyWith', () {
      expect(buildServer(), equals(buildServer()));
      expect(buildServer().hashCode, equals(buildServer().hashCode));
      final renamed = buildServer().copyWith(label: 'new-label');
      expect(renamed.label, 'new-label');
      expect(renamed.id, 'id-1');
      expect(buildServer(), isNot(equals(renamed)));
    });

    test('nested entities participate in equality', () {
      final withMeta = buildServer().copyWith(metadata: buildMetadata());
      expect(withMeta, isNot(equals(buildServer())));
      expect(withMeta.metadata, equals(buildMetadata()));
    });
  });
}
