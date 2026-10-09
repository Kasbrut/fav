import 'package:fav/core/errors/app_exception.dart';
import 'package:fav/features/install/application/ssh_auth_resolver.dart';
import 'package:fav/features/install/application/wireguard_port_reachability_service.dart';
import 'package:fav/features/install/data/keys/ssh_key_repository.dart';
import 'package:fav/features/install/data/ssh/dart_ssh_client.dart';
import 'package:fav/features/install/data/ssh/host_key_change_registry.dart';
import 'package:fav/features/install/data/ssh/host_key_store.dart';
import 'package:fav/features/install/domain/ssh_client.dart';
import 'package:fav/features/peers/data/hive_peer_repository.dart';
import 'package:fav/features/peers/data/secure_peer_secret_repository.dart';
import 'package:fav/features/profile/data/secure_client_profile_repository.dart';
import 'package:fav/features/servers/data/hive_server_repository.dart';
import 'package:fav/features/servers/data/server_probe.dart';
import 'package:fav/features/servers/domain/host_key_fingerprint.dart';
import 'package:fav/features/servers/domain/server.dart';
import 'package:fav/features/servers/domain/wireguard_installation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Loads and mutates the list of registered servers.
class ServerListController extends AsyncNotifier<List<Server>> {
  @override
  Future<List<Server>> build() => _loadWithPinnedHostKeys();

  /// Reloads the server list from local storage.
  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(_loadWithPinnedHostKeys);
  }

  /// Host-key pins live in secure storage rather than the Hive server row.
  /// Reattach them whenever the list is loaded so the detail screen can show
  /// the active trust anchor after navigation or an app restart.
  Future<List<Server>> _loadWithPinnedHostKeys() async {
    final servers = await ref.read(serverRepositoryProvider).getAll();
    final store = ref.read(hostKeyStoreProvider);
    return Future.wait(
      servers.map((server) async {
        final pinned = await store.lookup(server.host, server.sshPort);
        return pinned == null ? server : server.copyWith(pinnedHostKey: pinned);
      }),
    );
  }

  /// Removes the server identified by [id] and reloads the list.
  ///
  /// Also evicts every per-server secret the app has stored: each peer's
  /// client profile (client private key + PSK) and its Hive row, the legacy
  /// single client profile, the app's Ed25519 SSH key seed, and the pinned
  /// SSH host-key fingerprint. Without this a "removed" server would leave
  /// orphan secrets in the OS keychain and orphan peer rows in Hive
  /// (spec §10.1; audit H3).
  Future<void> delete(String id) async {
    final existing = await ref.read(serverRepositoryProvider).getAll();
    final server = existing.where((s) => s.id == id).firstOrNull;
    await ref.read(serverRepositoryProvider).delete(id);
    // Best-effort cleanup: a keystore/Hive failure must not block the removal.
    try {
      await ref.read(clientProfileRepositoryProvider).delete(id);
    } on Object {
      // Swallow — the server record is already gone.
    }
    // Delete every peer's secret + row for this server.
    try {
      final peers = await ref.read(peerRepositoryProvider).getByServerId(id);
      for (final peer in peers) {
        try {
          await ref.read(peerSecretRepositoryProvider).delete(peer.id);
        } on Object {
          // Swallow — continue evicting the remaining peers.
        }
        try {
          await ref.read(peerRepositoryProvider).delete(peer.id);
        } on Object {
          // Swallow — continue evicting the remaining peers.
        }
      }
    } on Object {
      // Swallow — the server record is already gone.
    }
    // Delete the app's SSH key seed (keyed by sshKeyId == the server id).
    try {
      await ref.read(sshKeyRepositoryProvider).delete(server?.sshKeyId ?? id);
    } on Object {
      // Swallow — the server record is already gone.
    }
    if (server != null) {
      // The host-key store is keyed by host:port and shared across server
      // records, so only evict it when no other registered server still uses
      // the same endpoint — otherwise we strip a sibling's pinned key and its
      // SSH connections (monitor included) start failing as `unknown`.
      final sharedByAnother = existing.any(
        (s) =>
            s.id != id && s.host == server.host && s.sshPort == server.sshPort,
      );
      if (!sharedByAnother) {
        try {
          await ref
              .read(hostKeyStoreProvider)
              .delete(server.host, server.sshPort);
        } on Object {
          // Swallow — the server record is already gone.
        }
      }
    }
    await refresh();
  }

  /// Re-probes [server] and saves the refreshed metadata.
  ///
  /// When [server] carries a stored SSH key (hardening was applied) the
  /// resolver loads it from the keystore and [password] is ignored — the UI
  /// must skip the password prompt in that case. Otherwise [password] is
  /// required and is held in memory only for this call.
  ///
  /// Throws an [AppException] on connection, host key, probe or
  /// key-unavailable failures.
  Future<void> reprobe(Server server, {String? password}) async {
    final params = await ref
        .read(sshAuthResolverProvider)
        .resolve(server: server, password: password);
    final client = ref.read(sshClientFactoryProvider)();
    try {
      await client.connect(params);
      final metadata = await ref.read(serverProbeProvider).probe(client);
      await ref
          .read(serverRepositoryProvider)
          .save(
            server.copyWith(metadata: metadata, lastSeenAt: DateTime.now()),
          );
    } finally {
      // A HostKeyUnknownException propagates intact: the detail screen shows
      // the confirmation dialog and re-pins — mapping it to ERR-HOST-01 here
      // raised a false MITM alarm for a legacy MD5-era pin that merely needs
      // re-confirmation after the SHA-256 migration (audit M3, seen live).
      await client.close();
    }
    await refresh();
  }

  /// Rechecks the installed WireGuard UDP port from this device.
  ///
  /// A conclusive result is persisted. [password] is used only for sudo when
  /// key-based SSH is already available; it is never stored.
  Future<WireguardPortReachability> checkWireguardPort(
    Server server, {
    String? password,
  }) async {
    final installation = server.installation;
    if (installation == null) return WireguardPortReachability.unknown;
    final params = await ref
        .read(sshAuthResolverProvider)
        .resolve(server: server, password: password);
    final client = ref.read(sshClientFactoryProvider)();
    try {
      await client.connect(params);
      final result = await const WireguardPortReachabilityService().check(
        client: client,
        endpoint: installation.publicEndpoint ?? server.host,
        port: installation.listenPort,
        useSudo: server.username != 'root',
        sudoPassword: server.username == 'root' ? null : password,
      );
      if (result != WireguardPortReachability.unknown) {
        await ref
            .read(serverRepositoryProvider)
            .save(
              server.copyWith(
                installation: installation.copyWith(
                  portReachability: result,
                  portCheckedAt: DateTime.now(),
                ),
              ),
            );
        await refresh();
      }
      return result;
    } finally {
      await client.close();
    }
  }

  /// Connects without changing trust and returns a newly received host key
  /// when it differs from the active pin. A matching key completes normally
  /// and returns `null`; every other connection error remains an error.
  Future<HostKeyFingerprint?> probeHostKeyChange(
    Server server, {
    String? password,
  }) async {
    final params = await ref
        .read(sshAuthResolverProvider)
        .resolve(server: server, password: password);
    final client = ref.read(sshClientFactoryProvider)();
    try {
      await client.connect(params);
      return null;
    } on HostKeyMismatchException catch (error) {
      return error.received;
    } finally {
      await client.close();
    }
  }

  /// Replaces a verified host-key pin and immediately proves that the normal
  /// authenticated connection still works. Any failure restores the old pin;
  /// the server record is updated only after the authenticated probe succeeds.
  Future<void> replaceHostKey(
    Server server,
    HostKeyFingerprint replacement, {
    String? password,
  }) async {
    final store = ref.read(hostKeyStoreProvider);
    final previous = await store.lookup(server.host, server.sshPort);
    await store.pin(replacement);
    try {
      await reprobe(
        server.copyWith(pinnedHostKey: replacement),
        password: password,
      );
      ref
          .read(hostKeyChangeRegistryProvider.notifier)
          .clear(server.host, server.sshPort);
    } on Object {
      if (previous == null) {
        await store.delete(server.host, server.sshPort);
      } else {
        await store.pin(previous);
      }
      rethrow;
    }
  }
}

/// Controls the list of registered servers.
final serverListControllerProvider =
    AsyncNotifierProvider<ServerListController, List<Server>>(
      ServerListController.new,
    );
