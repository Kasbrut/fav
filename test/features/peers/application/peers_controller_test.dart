import 'dart:async';

import 'package:fav/core/crypto/ed25519_keypair.dart';
import 'package:fav/core/errors/app_exception.dart';
import 'package:fav/core/wireguard/wg_public_key.dart';
import 'package:fav/features/install/data/keys/ssh_key_repository.dart';
import 'package:fav/features/install/data/scripts/effective_script_resolver.dart';
import 'package:fav/features/install/data/ssh/dart_ssh_client.dart';
import 'package:fav/features/install/domain/ssh_client.dart';
import 'package:fav/features/peers/application/peers_controller.dart';
import 'package:fav/features/peers/data/hive_peer_repository.dart';
import 'package:fav/features/peers/data/peer_script_source.dart';
import 'package:fav/features/peers/data/secure_peer_secret_repository.dart';
import 'package:fav/features/peers/domain/peer.dart';
import 'package:fav/features/peers/domain/peer_repository.dart';
import 'package:fav/features/peers/domain/peer_secret_repository.dart';
import 'package:fav/features/servers/data/hive_server_repository.dart';
import 'package:fav/features/servers/domain/server.dart';
import 'package:fav/features/servers/domain/wireguard_installation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_effective_scripts.dart';
import '../../../support/in_memory_user_script_repository.dart';
import '../../../support/peer_script_bundle.dart';
import '../../../support/recording_ssh_client.dart';
import '../../../support/server_fakes.dart';

class _InMemoryPeerRepository implements PeerRepository {
  final Map<String, Peer> _peers = {};

  @override
  Future<List<Peer>> getAll() async {
    final list = _peers.values.toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return list;
  }

  @override
  Future<Peer?> getById(String id) async => _peers[id];

  @override
  Future<List<Peer>> getByServerId(String serverId) async {
    final list = _peers.values.where((p) => p.serverId == serverId).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return list;
  }

  @override
  Future<void> save(Peer peer) async {
    _peers[peer.id] = peer;
  }

  @override
  Future<void> delete(String id) async {
    _peers.remove(id);
  }
}

class _InMemoryPeerSecrets implements PeerSecretRepository {
  final Map<String, String> _entries = {};

  @override
  Future<void> save({required String peerId, required String rawConf}) async {
    _entries[peerId] = rawConf;
  }

  @override
  Future<String?> read(String peerId) async => _entries[peerId];

  @override
  Future<void> delete(String peerId) async {
    _entries.remove(peerId);
  }
}

class _FakeSshKeyRepository implements SshKeyRepository {
  @override
  Future<Ed25519KeyPair?> get(String serverId) async => null;

  @override
  Future<Ed25519KeyPair> getOrCreate({
    required String serverId,
    required String comment,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> delete(String serverId) async {}
}

const _envelope = '''
ADDR=10.13.13.3/32
PUBKEY=NEW-PEER-PUB
---BEGIN-CONF---
[Interface]
PrivateKey = AAA=
Address = 10.13.13.3/32
DNS = 1.1.1.1
MTU = 1420

[Peer]
PublicKey = SERVER-PUB
PresharedKey = BBB=
Endpoint = vpn.example.org:51820
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
---END-CONF---
''';

Server testServer({String id = 'srv-1', String host = 'vpn.example.org'}) {
  return Server(
    id: id,
    label: 'vps',
    host: host,
    sshPort: 22,
    username: 'root',
    createdAt: DateTime.utc(2026, 5, 26),
  );
}

class _Fixture {
  _Fixture({
    SshCommandResult Function(String command)? onRun,
    PeerRepository? peers,
    PeerSecretRepository? secrets,
    FakeServerRepository? servers,
  }) : peers = peers ?? _InMemoryPeerRepository(),
       secrets = secrets ?? _InMemoryPeerSecrets(),
       servers = servers ?? FakeServerRepository(),
       sshClient = RecordingSshClient(onRun: onRun ?? _defaultOnRun) {
    container = ProviderContainer(
      overrides: [
        peerRepositoryProvider.overrideWithValue(this.peers),
        peerSecretRepositoryProvider.overrideWithValue(this.secrets),
        serverRepositoryProvider.overrideWithValue(this.servers),
        sshClientFactoryProvider.overrideWithValue(() => sshClient),
        peerScriptSourceProvider.overrideWithValue(
          PeerScriptSource(
            bundle: FakePeerAssetBundle(),
            expectedHashes: const {},
          ),
        ),
        effectiveScriptResolverProvider.overrideWith(
          (ref) async => fakeResolver(InMemoryUserScriptRepository()),
        ),
        sshKeyRepositoryProvider.overrideWithValue(_FakeSshKeyRepository()),
      ],
    );
  }

  final PeerRepository peers;
  final PeerSecretRepository secrets;
  final FakeServerRepository servers;
  final RecordingSshClient sshClient;
  late final ProviderContainer container;

  static SshCommandResult _defaultOnRun(String command) {
    if (command.contains('mkdir -m 700')) {
      return const SshCommandResult(
        stdout: 'WG-PEER-STAGED\n',
        stderr: '',
        exitCode: 0,
      );
    }
    if (command.startsWith('sudo')) {
      return const SshCommandResult(
        stdout: _envelope,
        stderr: '',
        exitCode: 0,
      );
    }
    return const SshCommandResult(stdout: '', stderr: '', exitCode: 0);
  }
}

void main() {
  setUp(() async {
    // Discard previous TestWidgetsFlutterBinding state.
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  test('build returns the current peers for the requested server', () async {
    final fixture = _Fixture();
    await fixture.servers.save(testServer());
    await fixture.peers.save(
      Peer(
        id: 'p1',
        serverId: 'srv-1',
        label: 'phone',
        address: '10.13.13.2/32',
        publicKey: 'PUB',
        createdAt: DateTime.utc(2026, 5, 26, 10),
      ),
    );
    final list = await fixture.container.read(
      peersControllerProvider('srv-1').future,
    );
    expect(list, hasLength(1));
    expect(list.single.id, 'p1');
  });

  test('addPeer rejects an invalid label', () async {
    final fixture = _Fixture();
    await fixture.servers.save(testServer());
    await fixture.container.read(peersControllerProvider('srv-1').future);
    final notifier = fixture.container.read(
      peersControllerProvider('srv-1').notifier,
    );
    await expectLater(
      notifier.addPeer(label: '', password: 'pw'),
      throwsA(
        predicate(
          (e) => e is AppException && e.code == ErrorCode.peerLabelInvalid,
        ),
      ),
    );
  });

  test('future v2 metadata never reaches peer mutation scripts', () async {
    for (final network in [
      const NetworkConfiguration(
        schemaVersion: 3,
        status: NetworkMetadataStatus.unsupported,
      ),
    ]) {
      final fixture = _Fixture();
      final installation = WireguardInstallation(
        interfaceName: 'wg0',
        listenPort: 51820,
        vpnSubnet: '10.13.13.0/24',
        serverPublicKey: 'key',
        peers: const [],
        hardeningApplied: false,
        installedAt: DateTime.utc(2026),
        network: network,
      );
      await fixture.servers.save(
        testServer().copyWith(installation: installation),
      );
      await fixture.container.read(peersControllerProvider('srv-1').future);

      await expectLater(
        fixture.container
            .read(peersControllerProvider('srv-1').notifier)
            .addPeer(label: 'phone', password: 'pw'),
        throwsA(
          isA<AppException>().having(
            (error) => error.code,
            'code',
            ErrorCode.peerApplyFailed,
          ),
        ),
      );
      expect(fixture.sshClient.runCommands, isEmpty);
      expect(fixture.sshClient.uploads, isEmpty);
    }
  });

  test('v2 add reuses its secure operation id after a lost response', () async {
    const privateKey = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=';
    final publicKey = await WgPublicKey.fromPrivateKey(privateKey);
    var attempts = 0;
    final fixture = _Fixture(
      onRun: (command) {
        if (command.contains('mkdir -m 700')) {
          return const SshCommandResult(
            stdout: 'WG-PEER-STAGED\n',
            stderr: '',
            exitCode: 0,
          );
        }
        if (!command.startsWith('sudo')) {
          return const SshCommandResult(stdout: '', stderr: '', exitCode: 0);
        }
        attempts++;
        final operation = RegExp(
          "FAV_OPERATION_ID='([^']+)'",
        ).firstMatch(command)!.group(1)!;
        if (attempts == 1) {
          return const SshCommandResult(
            stdout: 'lost response',
            stderr: '',
            exitCode: 0,
          );
        }
        return SshCommandResult(
          stdout:
              '''
FAV_ENVELOPE_VERSION=2
INSTALLATION_ID=installation-1
OPERATION_ID=$operation
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
''',
          stderr: '',
          exitCode: 0,
        );
      },
    );
    final network = NetworkConfiguration(
      schemaVersion: 2,
      installationId: 'installation-1',
      revision: 1,
      ipv6Mode: Ipv6Mode.blocked,
      ipv4Subnet: '10.13.13.0/24',
      ipv6Subnet: 'fd12:3456:789a::/64',
      fallbackIpv6Subnet: 'fd12:3456:789a::/64',
      serverIpv6Address: 'fd12:3456:789a::1/64',
      capabilityStatus: CapabilityStatus.unknown,
      capabilityReason: 'test',
      capabilityCheckedAt: DateTime.utc(2026, 9, 17),
      status: NetworkMetadataStatus.valid,
    );
    final installation = WireguardInstallation(
      interfaceName: 'wg0',
      listenPort: 51820,
      vpnSubnet: '10.13.13.0/24',
      serverPublicKey: privateKey,
      peers: const [],
      hardeningApplied: false,
      installedAt: DateTime.utc(2026),
      network: network,
    );
    await fixture.servers.save(
      testServer().copyWith(installation: installation),
    );
    await fixture.container.read(peersControllerProvider('srv-1').future);
    final notifier = fixture.container.read(
      peersControllerProvider('srv-1').notifier,
    );
    await expectLater(
      notifier.addPeer(label: 'phone', password: 'pw'),
      throwsA(isA<AppException>()),
    );
    final peer = await notifier.addPeer(label: 'phone', password: 'pw');
    expect(peer.ipv6Address, 'fd12:3456:789a::2/128');
    final commands = fixture.sshClient.runCommands
        .where((value) => value.startsWith('sudo'))
        .toList();
    final ids = commands
        .map(
          (value) =>
              RegExp("FAV_OPERATION_ID='([^']+)'").firstMatch(value)!.group(1),
        )
        .toSet();
    expect(ids, hasLength(1));
  });

  test('addPeer happy path: SSH runs, peer saved, list refreshes', () async {
    final fixture = _Fixture();
    await fixture.servers.save(testServer());
    await fixture.container.read(peersControllerProvider('srv-1').future);
    final notifier = fixture.container.read(
      peersControllerProvider('srv-1').notifier,
    );
    final peer = await notifier.addPeer(label: 'phone', password: 'pw');
    expect(peer.serverId, 'srv-1');
    expect(peer.label, 'phone');
    expect(peer.address, '10.13.13.3/32');
    expect(peer.publicKey, 'NEW-PEER-PUB');
    // The runner uploaded the script + ran the sudo command.
    expect(fixture.sshClient.uploads, isNotEmpty);
    expect(
      fixture.sshClient.runCommands.any((c) => c.startsWith('sudo')),
      isTrue,
    );
    // Peer + secret are persisted; state reflects the new list.
    expect((await fixture.peers.getByServerId('srv-1')).single.id, peer.id);
    expect(await fixture.secrets.read(peer.id), contains('[Interface]'));
    final state = fixture.container.read(peersControllerProvider('srv-1'));
    expect(state.requireValue.single.id, peer.id);
  });

  test(
    'addPeer reuses the first peer conf endpoint, not server.host (M6)',
    () async {
      // A server added by internal IP but installed with a custom public
      // endpoint: later peers must point at the public endpoint (carried by the
      // first peer's conf), not the internal server.host.
      final fixture = _Fixture();
      await fixture.servers.save(testServer(host: '10.0.0.5'));
      await fixture.peers.save(
        Peer(
          id: 'p1',
          serverId: 'srv-1',
          label: 'first',
          address: '10.13.13.2/32',
          publicKey: 'FIRST-PUB',
          createdAt: DateTime.utc(2026, 5, 26, 9),
        ),
      );
      // Valid 32-byte base64 keys so ClientProfileParser accepts the conf.
      const key = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=';
      await fixture.secrets.save(
        peerId: 'p1',
        rawConf:
            '[Interface]\n'
            'PrivateKey = $key\n'
            'Address = 10.13.13.2/32\n'
            'DNS = 1.1.1.1\n'
            'MTU = 1420\n'
            '\n'
            '[Peer]\n'
            'PublicKey = $key\n'
            'PresharedKey = $key\n'
            'Endpoint = vpn.example.org:51820\n'
            'AllowedIPs = 0.0.0.0/0\n',
      );
      await fixture.container.read(peersControllerProvider('srv-1').future);
      final notifier = fixture.container.read(
        peersControllerProvider('srv-1').notifier,
      );

      await notifier.addPeer(label: 'laptop', password: 'pw');

      final sudo = fixture.sshClient.runCommands.firstWhere(
        (c) => c.startsWith('sudo'),
      );
      expect(sudo, contains("PUBLIC_ENDPOINT='vpn.example.org'"));
      expect(sudo, isNot(contains("PUBLIC_ENDPOINT='10.0.0.5'")));
    },
  );

  test('revokePeer removes the server-side peer and the local entry', () async {
    final fixture = _Fixture();
    await fixture.servers.save(testServer());
    final peer = Peer(
      id: 'p1',
      serverId: 'srv-1',
      label: 'phone',
      address: '10.13.13.2/32',
      publicKey: 'PEER-PUB',
      createdAt: DateTime.utc(2026, 5, 26),
    );
    await fixture.peers.save(peer);
    await fixture.secrets.save(peerId: 'p1', rawConf: '[Interface]\n');
    await fixture.container.read(peersControllerProvider('srv-1').future);

    await fixture.container
        .read(peersControllerProvider('srv-1').notifier)
        .revokePeer(peer: peer, password: 'pw');

    expect(await fixture.peers.getByServerId('srv-1'), isEmpty);
    expect(await fixture.secrets.read('p1'), isNull);
    // The SSH script ran under sudo with PEER_PUBKEY=PEER-PUB.
    final sudo = fixture.sshClient.runCommands.firstWhere(
      (c) => c.startsWith('sudo'),
    );
    expect(sudo, contains("PEER_PUBKEY='PEER-PUB'"));
  });

  test(
    'revokePeer succeeds locally when the server reports not-found',
    () async {
      final fixture = _Fixture(
        onRun: (command) {
          if (command.contains('mkdir -m 700')) {
            return const SshCommandResult(
              stdout: 'WG-PEER-STAGED\n',
              stderr: '',
              exitCode: 0,
            );
          }
          if (command.startsWith('sudo')) {
            return const SshCommandResult(
              stdout: '',
              stderr: 'ERR-PEER-NOT-FOUND\n',
              exitCode: 42,
            );
          }
          return const SshCommandResult(stdout: '', stderr: '', exitCode: 0);
        },
      );
      await fixture.servers.save(testServer());
      final peer = Peer(
        id: 'p1',
        serverId: 'srv-1',
        label: 'phone',
        address: '10.13.13.2/32',
        publicKey: 'PEER-PUB',
        createdAt: DateTime.utc(2026, 5, 26),
      );
      await fixture.peers.save(peer);
      await fixture.secrets.save(peerId: 'p1', rawConf: '[Interface]\n');
      await fixture.container.read(peersControllerProvider('srv-1').future);

      await fixture.container
          .read(peersControllerProvider('srv-1').notifier)
          .revokePeer(peer: peer, password: 'pw');

      expect(await fixture.peers.getByServerId('srv-1'), isEmpty);
    },
  );

  test('renamePeer updates only the targeted entry', () async {
    final fixture = _Fixture();
    await fixture.servers.save(testServer());
    final p1 = Peer(
      id: 'p1',
      serverId: 'srv-1',
      label: 'phone',
      address: '10.13.13.2/32',
      publicKey: 'PUB1',
      createdAt: DateTime.utc(2026, 5, 26, 10),
    );
    final p2 = Peer(
      id: 'p2',
      serverId: 'srv-1',
      label: 'laptop',
      address: '10.13.13.3/32',
      publicKey: 'PUB2',
      createdAt: DateTime.utc(2026, 5, 26, 11),
    );
    await fixture.peers.save(p1);
    await fixture.peers.save(p2);
    await fixture.container.read(peersControllerProvider('srv-1').future);

    await fixture.container
        .read(peersControllerProvider('srv-1').notifier)
        .renamePeer(peer: p1, newLabel: 'iPhone 15');

    final list = await fixture.peers.getByServerId('srv-1');
    expect(
      list.firstWhere((p) => p.id == 'p1').label,
      'iPhone 15',
    );
    expect(list.firstWhere((p) => p.id == 'p2').label, 'laptop');
  });

  test('two concurrent mutations execute one at a time', () async {
    // Use a controller-level mutation that holds the queue while we measure.
    final fixture = _Fixture();
    await fixture.servers.save(testServer());
    await fixture.container.read(peersControllerProvider('srv-1').future);
    final notifier = fixture.container.read(
      peersControllerProvider('srv-1').notifier,
    );

    final completer = Completer<int>();
    final first = notifier.runSerialised(() async {
      await completer.future;
      return 1;
    });
    final secondQueued = notifier.runSerialised(() async => 2);
    // While `first` is parked on the completer, no other mutation has run.
    await Future<void>.delayed(Duration.zero);
    expect(notifier.activeMutations, 1);
    completer.complete(0);
    expect(await first, 1);
    expect(await secondQueued, 2);
  });
}
