import 'dart:typed_data';

import 'package:fav/features/install/data/scripts/asset_script_repository.dart';
import 'package:fav/features/install/domain/script_source.dart';
import 'package:fav/features/install/domain/ssh_client.dart';
import 'package:fav/features/install/domain/ssh_shell_session.dart';
import 'package:fav/features/servers/data/server_probe.dart';
import 'package:fav/features/servers/domain/host_key_fingerprint.dart';
import 'package:fav/features/servers/domain/server.dart';
import 'package:fav/features/servers/domain/server_metadata.dart';
import 'package:fav/features/servers/domain/server_repository.dart';
import 'package:fav/features/servers/domain/wireguard_installation.dart';

/// In-memory [ServerRepository] for tests.
class FakeServerRepository implements ServerRepository {
  final List<Server> _servers = [];

  @override
  Future<List<Server>> getAll() async => List.unmodifiable(_servers);

  @override
  Future<Server?> getById(String id) async {
    final matches = _servers.where((server) => server.id == id);
    return matches.isEmpty ? null : matches.first;
  }

  @override
  Future<void> save(Server server) async {
    _servers
      ..removeWhere((existing) => existing.id == server.id)
      ..add(server);
  }

  @override
  Future<void> delete(String id) async {
    _servers.removeWhere((server) => server.id == id);
  }
}

/// [SshClient] stub: [connect] throws [connectError] when set, else succeeds.
class StubSshClient implements SshClient {
  /// Creates a [StubSshClient] that fails to connect with [connectError].
  StubSshClient({this.connectError});

  /// Error thrown by [connect]; `null` means the connection succeeds.
  final Exception? connectError;

  @override
  Future<void> connect(SshConnectionParams params) async {
    final error = connectError;
    if (error != null) {
      throw error;
    }
  }

  @override
  Future<SshCommandResult> run(String command, {String? stdin}) async {
    return const SshCommandResult(stdout: '', stderr: '', exitCode: 0);
  }

  @override
  Future<void> uploadBytes({
    required String remotePath,
    required List<int> data,
  }) async {}

  @override
  Future<SshShellSession> startShell({int columns = 80, int rows = 24}) async {
    throw UnimplementedError('StubSshClient does not support shells');
  }

  @override
  Future<void> close() async {}
}

/// [ServerProbe] stub: returns [metadata] or throws [error].
class StubServerProbe extends ServerProbe {
  /// Creates a [StubServerProbe].
  const StubServerProbe({this.metadata, this.error});

  /// Metadata returned by [probe] on success.
  final ServerMetadata? metadata;

  /// Error thrown by [probe]; `null` means the probe succeeds.
  final Exception? error;

  @override
  Future<ServerMetadata> probe(SshClient client) async {
    final failure = error;
    if (failure != null) {
      throw failure;
    }
    return metadata!;
  }
}

/// Builds a [ServerMetadata] for tests.
ServerMetadata testMetadata() {
  return ServerMetadata(
    osId: 'debian',
    osVersion: '12',
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
}

/// Builds a [Server] for tests.
Server testServer({
  String id = 'srv-1',
  String label = 'vps-test',
  String username = 'root',
}) {
  return Server(
    id: id,
    label: label,
    host: '203.0.113.5',
    sshPort: 22,
    username: username,
    createdAt: DateTime(2026, 5, 18),
  );
}

/// Builds a hardened [Server] that carries FAV's deployed app key.
///
/// `sshKeyId` is set (FAV's app key will be removed), the recorded
/// installation has `hardeningApplied = true` (password login is off), and
/// [ownKeys] populates `userAuthorizedKeys`. With no own keys and no re-open,
/// the teardown lockout guard trips for this server.
Server hardenedServerWithAppKey({
  String id = 'srv-hard',
  List<String> ownKeys = const [],
}) {
  return Server(
    id: id,
    label: 'hardened-vps',
    host: '203.0.113.7',
    sshPort: 22,
    username: 'wgadmin',
    createdAt: DateTime(2026, 5, 18),
    sshKeyId: id,
    userAuthorizedKeys: ownKeys,
    installation: WireguardInstallation(
      interfaceName: 'wg0',
      listenPort: 51820,
      vpnSubnet: '10.13.13.0/24',
      serverPublicKey: 'pub',
      peers: const [],
      hardeningApplied: true,
      installedAt: DateTime(2026, 5, 18),
    ),
  );
}

/// Builds a minimal [ScriptBundle] containing a `reopen_ssh.sh` asset so the
/// teardown controller's `firstWhere`/`bytesFor` lookup resolves in tests.
ScriptBundle fakeReopenBundle() {
  return ScriptBundle(
    assets: [
      ScriptAsset(
        relativePath: kReopenSshScript,
        bytes: Uint8List.fromList('#!/usr/bin/env bash\n'.codeUnits),
      ),
    ],
    bundleHash: 'fake-bundle-hash',
  );
}

/// Builds a [ScriptBundle] containing the teardown orchestrator,
/// `lib/common.sh` and every teardown module so the services-teardown
/// service's asset lookups resolve in tests.
ScriptBundle fakeTeardownBundle() {
  ScriptAsset stub(String relativePath) => ScriptAsset(
    relativePath: relativePath,
    bytes: Uint8List.fromList('#!/usr/bin/env bash\n'.codeUnits),
  );
  return ScriptBundle(
    assets: [
      stub(kTeardownOrchestratorScript),
      stub('lib/common.sh'),
      stub('lib/firewall_manager.py'),
      for (final relPath in kTeardownModuleManifest) stub(relPath),
    ],
    bundleHash: 'fake-teardown-bundle-hash',
  );
}

/// Builds a [HostKeyFingerprint] for tests, defaulting to [testServer]'s
/// endpoint so it lines up with a server's `host:port`.
HostKeyFingerprint testFingerprint({
  String host = '203.0.113.5',
  int port = 22,
  String fingerprint = 'AA:BB:CC',
}) {
  return HostKeyFingerprint(
    host: host,
    port: port,
    keyType: 'ssh-ed25519',
    hashAlgorithm: 'sha256',
    fingerprint: fingerprint,
    pinnedAt: DateTime(2026, 5, 18),
  );
}
