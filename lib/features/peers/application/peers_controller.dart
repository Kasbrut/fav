import 'dart:async';

import 'package:fav/core/errors/app_exception.dart';
import 'package:fav/core/utils/app_logger.dart';
import 'package:fav/core/utils/validators.dart';
import 'package:fav/features/install/application/ssh_auth_resolver.dart';
import 'package:fav/features/install/data/scripts/editable_script_catalog.dart';
import 'package:fav/features/install/data/scripts/effective_script_resolver.dart';
import 'package:fav/features/install/data/ssh/dart_ssh_client.dart';
import 'package:fav/features/peers/data/hive_peer_repository.dart';
import 'package:fav/features/peers/data/peer_script_source.dart';
import 'package:fav/features/peers/data/secure_peer_secret_repository.dart';
import 'package:fav/features/peers/data/ssh/peer_add_runner.dart';
import 'package:fav/features/peers/data/ssh/peer_revoke_runner.dart';
import 'package:fav/features/peers/domain/peer.dart';
import 'package:fav/features/profile/data/client_profile_parser.dart';
import 'package:fav/features/servers/data/hive_server_repository.dart';
import 'package:fav/features/servers/domain/network_configuration_validator.dart';
import 'package:fav/features/servers/domain/server.dart';
import 'package:fav/features/servers/domain/wireguard_installation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:logger/logger.dart';
import 'package:meta/meta.dart';
import 'package:uuid/uuid.dart';

/// Default DNS to write into a peer's `client.conf` when the server has no
/// existing peer to copy the value from. Mirrors the install default.
const String _defaultDns = '1.1.1.1, 1.0.0.1';

/// Default MTU to write into a peer's `client.conf` when the server has no
/// existing peer to copy the value from. Mirrors the install default.
const int _defaultMtu = 1420;

/// Default WireGuard listen port when the server record has no installation.
const int _defaultWgPort = 51820;

/// Default WireGuard interface name when the server record has no
/// installation.
const String _defaultInterfaceName = 'wg0';

/// Default VPN subnet when the server record has no installation. Matches
/// the install default in spec §8.2.
const String _defaultVpnSubnet = '10.13.13.0/24';

/// Per-server async list of peers, plus the add/revoke/rename mutations.
///
/// Mutations are serialised per `serverId` so a fast-tapping user can't fire
/// two concurrent add/revoke commands that would race in the SSH session;
/// the in-process mutex complements the per-interface `flock` enforced by
/// the bash scripts.
class PeersController extends AsyncNotifier<List<Peer>> {
  /// Creates a controller for the server identified by [arg].
  PeersController(this.arg);

  /// The server id this controller is scoped to (family argument).
  final String arg;

  /// Future-chain serialising every mutation against this controller.
  Future<void> _mutationQueue = Future<void>.value();

  /// In-process counter so tests can assert serialisation.
  int _activeMutations = 0;

  /// Serialises [body] against any other in-flight mutation on this
  /// controller. Exposed for tests.
  @visibleForTesting
  Future<T> runSerialised<T>(Future<T> Function() body) async {
    final completer = Completer<T>();
    final previous = _mutationQueue;
    _mutationQueue = previous.then((_) async {
      _activeMutations++;
      try {
        final value = await body();
        completer.complete(value);
      } on Object catch (error, stack) {
        completer.completeError(error, stack);
      } finally {
        _activeMutations--;
      }
    });
    return completer.future;
  }

  /// Number of mutations currently executing (always ≤ 1 thanks to the
  /// serialisation queue). Used by tests.
  @visibleForTesting
  int get activeMutations => _activeMutations;

  @override
  Future<List<Peer>> build() async {
    return ref.read(peerRepositoryProvider).getByServerId(arg);
  }

  Logger get _logger => ref.read(_peersLoggerProvider);

  Uuid get _uuid => ref.read(_uuidProvider);

  /// Adds a new peer to the server identified by [arg], using [password]
  /// for both SSH (when no key is stored) and `sudo -S` on the server.
  ///
  /// Returns the freshly created [Peer]. Throws an [AppException] when the
  /// server-side script reports a known failure; the original exception
  /// is propagated otherwise.
  Future<Peer> addPeer({
    required String label,
    required String password,
  }) {
    return runSerialised(
      () => _addPeerLocked(label: label, password: password),
    );
  }

  Future<Peer> _addPeerLocked({
    required String label,
    required String password,
  }) async {
    final trimmed = label.trim();
    if (!isValidPeerLabel(trimmed)) {
      throw const AppException(ErrorCode.peerLabelInvalid);
    }
    final server = await _requireServer();
    final isV2 = _requireSupportedMutationPath(server);
    final params = await ref
        .read(sshAuthResolverProvider)
        .resolve(server: server, password: password);
    final ssh = ref.read(sshClientFactoryProvider)();
    await ssh.connect(params);
    try {
      final defaults = isV2
          ? _PeerDefaults(
              interfaceName: server.installation!.interfaceName,
              vpnSubnet: '',
              wgPort: 0,
              dns: '',
              mtu: 0,
              publicEndpoint: '',
            )
          : await _resolveDefaults(server);
      final pendingKey = '_fav_pending_add_${server.id}';
      final savedOperation = isV2
          ? await ref.read(peerSecretRepositoryProvider).read(pendingKey)
          : null;
      final operationId = isV2 ? (savedOperation ?? _uuid.v4()) : null;
      if (isV2 && savedOperation == null) {
        await ref
            .read(peerSecretRepositoryProvider)
            .save(peerId: pendingKey, rawConf: operationId!);
      }
      final network = server.installation?.network;
      final request = PeerAddRequest(
        interfaceName: defaults.interfaceName,
        vpnSubnet: defaults.vpnSubnet,
        publicEndpoint: defaults.publicEndpoint,
        wgPort: defaults.wgPort,
        dns: defaults.dns,
        mtu: defaults.mtu,
        label: trimmed,
        installationId: isV2 ? network!.installationId : null,
        operationId: operationId,
        network: isV2 ? network : null,
      );
      final runner = PeerAddRunner(
        scriptSource: ref.read(peerScriptSourceProvider),
      );
      final overrideBytes = isV2
          ? null
          : await (await ref.read(
              effectiveScriptResolverProvider.future,
            )).bytesFor(kPeerAddScript);
      final envelope = await runner.run(
        ssh: ssh,
        password: password,
        request: request,
        overrideBytes: overrideBytes,
      );
      final peer = Peer(
        id: _uuid.v4(),
        serverId: server.id,
        label: trimmed,
        address: envelope.address,
        ipv6Address: envelope.ipv6Address,
        publicKey: envelope.publicKey,
        createdAt: DateTime.now(),
      );
      await ref
          .read(peerSecretRepositoryProvider)
          .save(peerId: peer.id, rawConf: envelope.rawConf);
      await ref.read(peerRepositoryProvider).save(peer);
      if (isV2) {
        await ref.read(peerSecretRepositoryProvider).delete(pendingKey);
      }
      state = AsyncData(
        await ref.read(peerRepositoryProvider).getByServerId(server.id),
      );
      return peer;
    } finally {
      await ssh.close();
    }
  }

  /// Revokes [peer]: removes it from the server, deletes the local
  /// metadata + secret. Returns normally when the server reports "not
  /// found" — the local cleanup still happens (the server is now in the
  /// goal state regardless).
  Future<void> revokePeer({
    required Peer peer,
    required String password,
  }) {
    return runSerialised(
      () => _revokePeerLocked(peer: peer, password: password),
    );
  }

  Future<void> _revokePeerLocked({
    required Peer peer,
    required String password,
  }) async {
    final server = await _requireServer();
    final isV2 = _requireSupportedMutationPath(server);
    final params = await ref
        .read(sshAuthResolverProvider)
        .resolve(server: server, password: password);
    final ssh = ref.read(sshClientFactoryProvider)();
    await ssh.connect(params);
    try {
      final runner = PeerRevokeRunner(
        scriptSource: ref.read(peerScriptSourceProvider),
      );
      final defaults = isV2
          ? _PeerDefaults(
              interfaceName: server.installation!.interfaceName,
              vpnSubnet: '',
              wgPort: 0,
              dns: '',
              mtu: 0,
              publicEndpoint: '',
            )
          : await _resolveDefaults(server);
      final overrideBytes = isV2
          ? null
          : await (await ref.read(
              effectiveScriptResolverProvider.future,
            )).bytesFor(kPeerRevokeScript);
      // We intentionally consume both ok and notFound the same way: the
      // user's goal is "this peer is gone", and both outcomes satisfy it.
      final pendingKey = '_fav_pending_revoke_${peer.id}';
      final savedOperation = isV2
          ? await ref.read(peerSecretRepositoryProvider).read(pendingKey)
          : null;
      final operationId = isV2 ? (savedOperation ?? _uuid.v4()) : null;
      if (isV2 && savedOperation == null) {
        await ref
            .read(peerSecretRepositoryProvider)
            .save(peerId: pendingKey, rawConf: operationId!);
      }
      await runner.run(
        ssh: ssh,
        password: password,
        interfaceName: defaults.interfaceName,
        peerPublicKey: peer.publicKey,
        overrideBytes: overrideBytes,
        installationId: isV2
            ? server.installation!.network!.installationId
            : null,
        operationId: operationId,
      );
      if (isV2) {
        await ref.read(peerSecretRepositoryProvider).delete(pendingKey);
      }
    } finally {
      await ssh.close();
    }
    await ref.read(peerSecretRepositoryProvider).delete(peer.id);
    await ref.read(peerRepositoryProvider).delete(peer.id);
    state = AsyncData(
      await ref.read(peerRepositoryProvider).getByServerId(server.id),
    );
  }

  /// Renames [peer] locally. No SSH operation — the server-side `# label:`
  /// comment is forensic, not authoritative.
  Future<void> renamePeer({
    required Peer peer,
    required String newLabel,
  }) {
    return runSerialised(
      () => _renamePeerLocked(peer: peer, newLabel: newLabel),
    );
  }

  Future<void> _renamePeerLocked({
    required Peer peer,
    required String newLabel,
  }) async {
    final trimmed = newLabel.trim();
    if (!isValidPeerLabel(trimmed)) {
      throw const AppException(ErrorCode.peerLabelInvalid);
    }
    final updated = peer.copyWith(label: trimmed);
    await ref.read(peerRepositoryProvider).save(updated);
    state = AsyncData(
      await ref.read(peerRepositoryProvider).getByServerId(peer.serverId),
    );
  }

  Future<Server> _requireServer() async {
    final server = await ref.read(serverRepositoryProvider).getById(arg);
    if (server == null) {
      // The UI is keyed by an existing server, so we should never get here
      // except in a race with delete-server. Surface as a generic apply
      // failure rather than crashing the controller.
      _logger.w('PeersController: server $arg not found');
      throw const AppException(
        ErrorCode.peerApplyFailed,
        detail: 'server not found',
      );
    }
    return server;
  }

  bool _requireSupportedMutationPath(Server server) {
    final network = server.installation?.network;
    if (network == null || network.status == NetworkMetadataStatus.legacy) {
      return false;
    }
    final problem = networkConfigurationV2Problem(network);
    if (problem != null) {
      throw AppException(
        ErrorCode.peerApplyFailed,
        detail: 'managed peer operation blocked: $problem',
      );
    }
    return true;
  }

  /// Resolves the env-var defaults the runner needs from the server record,
  /// falling back to the first peer's `.conf` (parsed) for DNS/MTU, then to
  /// the documented install defaults.
  Future<_PeerDefaults> _resolveDefaults(Server server) async {
    final installation = server.installation;
    final interfaceName = installation?.interfaceName ?? _defaultInterfaceName;
    final wgPort = installation?.listenPort ?? _defaultWgPort;
    final vpnSubnet = installation?.vpnSubnet ?? _defaultVpnSubnet;

    var dns = _defaultDns;
    var mtu = _defaultMtu;
    // The public endpoint the install chose is not persisted on the record, so
    // recover it from the first peer's conf `Endpoint = host:port` line —
    // otherwise a server added by internal IP but installed with a custom
    // public endpoint would point later peers at the wrong host (audit M6).
    var publicEndpoint = server.host;
    final existing = await ref
        .read(peerRepositoryProvider)
        .getByServerId(server.id);
    if (existing.isNotEmpty) {
      final first = existing.first;
      final raw = await ref.read(peerSecretRepositoryProvider).read(first.id);
      if (raw != null) {
        try {
          final profile = await const ClientProfileParser().parse(raw);
          if (profile.dns.isNotEmpty) {
            dns = profile.dns.join(', ');
          }
          mtu = profile.mtu;
          final host = _endpointHost(profile.endpoint);
          if (host.isNotEmpty) {
            publicEndpoint = host;
          }
        } on Object catch (error) {
          // Keep defaults if the existing conf is unparseable — the v1.0
          // parser already enforces a valid shape, so this is unexpected.
          _logger.w(
            'Could not parse first peer conf for defaults: '
            '${error.runtimeType}',
          );
        }
      }
    }
    return _PeerDefaults(
      interfaceName: interfaceName,
      vpnSubnet: vpnSubnet,
      wgPort: wgPort,
      dns: dns,
      mtu: mtu,
      publicEndpoint: publicEndpoint,
    );
  }

  /// Extracts the host from an `Endpoint = host:port` value, keeping a
  /// bracketed IPv6 literal (`[::1]:51820` → `[::1]`) intact.
  String _endpointHost(String endpoint) {
    final idx = endpoint.lastIndexOf(':');
    return idx > 0 ? endpoint.substring(0, idx) : endpoint;
  }
}

class _PeerDefaults {
  const _PeerDefaults({
    required this.interfaceName,
    required this.vpnSubnet,
    required this.wgPort,
    required this.dns,
    required this.mtu,
    required this.publicEndpoint,
  });
  final String interfaceName;
  final String vpnSubnet;
  final int wgPort;
  final String dns;
  final int mtu;
  final String publicEndpoint;
}

/// UUID provider used by [PeersController]; tests override it for stable ids.
final Provider<Uuid> _uuidProvider = Provider<Uuid>((ref) => const Uuid());

/// Logger seam.
final Provider<Logger> _peersLoggerProvider = Provider<Logger>(
  (ref) => appLogger,
);

/// Single per-server family provider for the peers list + mutations.
final AsyncNotifierProviderFamily<PeersController, List<Peer>, String>
peersControllerProvider = AsyncNotifierProvider.autoDispose
    .family<PeersController, List<Peer>, String>(PeersController.new);
