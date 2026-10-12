import 'dart:convert';
import 'dart:typed_data';

import 'package:fav/core/crypto/ed25519_keypair.dart';
import 'package:fav/core/persistence/secure_store.dart';
import 'package:fav/features/install/application/ssh_auth_resolver.dart';
import 'package:fav/features/install/data/keys/ssh_key_repository.dart';
import 'package:fav/features/install/data/ssh/dart_ssh_client.dart';
import 'package:fav/features/install/domain/ssh_client.dart';
import 'package:fav/features/peers/data/hive_peer_repository.dart';
import 'package:fav/features/peers/data/peer_script_source.dart';
import 'package:fav/features/peers/data/secure_peer_secret_repository.dart';
import 'package:fav/features/peers/data/ssh/peer_revoke_runner.dart';
import 'package:fav/features/servers/application/app_key_removal.dart';
import 'package:fav/features/servers/domain/server.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

const String _appendKeySnippet =
    r'cd "$HOME" || exit 1; umask 077; mkdir -p .ssh; '
    'touch .ssh/authorized_keys; chmod 700 .ssh; chmod 600 .ssh/authorized_keys; '
    r'key="$(cat)"; grep -qxF -- "$key" .ssh/authorized_keys '
    r'|| printf "%s\n" "$key" >> .ssh/authorized_keys';

const String _verifyKeyRemovedSnippet =
    r'cd "$HOME" || exit 2; f=.ssh/authorized_keys; '
    r'[ -f "$f" ] || exit 0; key="$(cat)"; '
    r'grep -qxF -- "$key" "$f"; status=$?; '
    r'[ "$status" -eq 1 ]';

/// Parses and validates the peer list returned by `wg show … peers`.
Set<String> parseWireGuardPeerKeys(String output) {
  final keys = output
      .split(RegExp(r'\s+'))
      .where((value) => value.isNotEmpty)
      .toSet();
  if (keys.any((value) => !RegExp(r'^[A-Za-z0-9+/]{43}=$').hasMatch(value))) {
    throw StateError('server returned an invalid WireGuard public key');
  }
  return keys;
}

/// Online checks and optional destructive recovery work after a restore.
class RestoreServerService {
  /// Creates the service from application dependencies.
  RestoreServerService(this._ref);

  final Ref _ref;

  /// Verifies pinned identity and authentication for [server].
  Future<void> verify(Server server, {String? password}) async {
    final params = await _ref
        .read(sshAuthResolverProvider)
        .resolve(server: server, password: password);
    final client = _ref.read(sshClientFactoryProvider)();
    try {
      await client.connect(params);
      final result = await client.run('true');
      if (!result.isSuccess) throw StateError('SSH verification failed');
    } finally {
      await client.close();
    }
  }

  /// Replaces FAV's restored SSH key without creating a lockout window.
  Future<void> rotateFavourKey(Server server) async {
    final keyId = server.sshKeyId;
    if (keyId == null) return;
    final repository = _ref.read(sshKeyRepositoryProvider);
    final oldPair = await repository.get(keyId);
    if (oldPair == null) throw StateError('restored SSH key is unavailable');
    final secureStore = _ref.read(secureStoreProvider);
    final pendingKey = 'ssh-rotation-pending:$keyId';
    final pending = await secureStore.read(pendingKey);
    final currentLine = oldPair.authorizedKeysEntry(
      comment: 'fav@${server.id}',
    );
    // Older versions only recorded the obsolete public line after committing.
    if (pending != null && pending.startsWith('ssh-ed25519 ')) {
      if (pending == currentLine) {
        throw StateError('rotation journal would revoke the current SSH key');
      }
      final cleanupClient = _ref.read(sshClientFactoryProvider)();
      try {
        await cleanupClient.connect(
          SshConnectionParams(
            host: server.host,
            port: server.sshPort,
            username: server.username,
            password: '',
            identities: [
              oldPair.asDartSshKeyPair(comment: 'fav@${server.id}'),
            ],
            passwordAuthAllowed: false,
          ),
        );
        await removeAppKeyFromAuthorizedKeys(
          client: cleanupClient,
          publicKeyLine: pending,
        );
        await _verifyKeyRemoved(cleanupClient, pending);
        await secureStore.delete(pendingKey);
        return;
      } finally {
        await cleanupClient.close();
      }
    }
    final Ed25519KeyPair newPair;
    final String oldLine;
    if (pending == null) {
      newPair = await Ed25519KeyPair.generate();
      oldLine = currentLine;
      // Write ahead of both remote installation and local seed replacement.
      // Recovery therefore retains the replacement even if the seed commit
      // failed, and never mistakes the still-current key for an obsolete one.
      await secureStore.write(
        pendingKey,
        jsonEncode({
          'version': 1,
          'oldLine': oldLine,
          'newSeed': base64Encode(newPair.seedBytes),
        }),
      );
    } else {
      try {
        final journal = jsonDecode(pending) as Map<String, dynamic>;
        if (journal['version'] != 1) throw const FormatException();
        oldLine = journal['oldLine'] as String;
        newPair = await Ed25519KeyPair.fromSeed(
          Uint8List.fromList(base64Decode(journal['newSeed'] as String)),
        );
      } on Object {
        // Do not expose a malformed journal's private seed in error details.
        throw StateError('invalid SSH rotation journal');
      }
    }
    final newLine = newPair.authorizedKeysEntry(comment: 'fav@${server.id}');
    if (oldLine == newLine ||
        (currentLine != oldLine && currentLine != newLine)) {
      throw StateError('SSH rotation journal does not match the stored key');
    }
    final oldClient = _ref.read(sshClientFactoryProvider)();
    try {
      await oldClient.connect(
        SshConnectionParams(
          host: server.host,
          port: server.sshPort,
          username: server.username,
          password: '',
          identities: [
            oldPair.asDartSshKeyPair(comment: 'fav@${server.id}'),
          ],
          passwordAuthAllowed: false,
        ),
      );
      final append = await oldClient.run(_appendKeySnippet, stdin: newLine);
      if (!append.isSuccess) throw StateError('new SSH key was not installed');
      final newClient = _ref.read(sshClientFactoryProvider)();
      try {
        await newClient.connect(
          SshConnectionParams(
            host: server.host,
            port: server.sshPort,
            username: server.username,
            password: '',
            identities: [
              newPair.asDartSshKeyPair(comment: 'fav@${server.id}'),
            ],
            passwordAuthAllowed: false,
          ),
        );
        // A crash on either side of this write is recoverable from the journal.
        // Keep the verified replacement connection for revocation as well.
        await secureStore.write(
          'ssh-key:$keyId',
          base64Encode(newPair.seedBytes),
        );
        await removeAppKeyFromAuthorizedKeys(
          client: newClient,
          publicKeyLine: oldLine,
        );
        await _verifyKeyRemoved(newClient, oldLine);
        await secureStore.delete(pendingKey);
      } finally {
        await newClient.close();
      }
    } finally {
      await oldClient.close();
    }
  }

  Future<void> _verifyKeyRemoved(SshClient client, String oldLine) async {
    final result = await client.run(_verifyKeyRemovedSnippet, stdin: oldLine);
    if (!result.isSuccess) {
      throw StateError('obsolete SSH key revocation could not be verified');
    }
  }

  /// Revokes every peer currently present on [server]. This intentionally
  /// queries the server instead of trusting the backup snapshot: a compromised
  /// old device may have created more peers after the backup was produced.
  Future<void> revokeRestoredPeers(
    Server server, {
    required String sudoPassword,
  }) async {
    final installation = server.installation;
    if (installation == null) return;
    final localPeers = await _ref
        .read(peerRepositoryProvider)
        .getByServerId(server.id);
    final params = await _ref
        .read(sshAuthResolverProvider)
        .resolve(server: server, password: sudoPassword);
    final client = _ref.read(sshClientFactoryProvider)();
    await client.connect(params);
    try {
      final interfaceName = installation.interfaceName;
      if (!RegExp(r'^[A-Za-z0-9_=+.-]{1,15}$').hasMatch(interfaceName)) {
        throw StateError('invalid WireGuard interface name');
      }
      final listed = await client.run(
        "sudo -S -p '' wg show '$interfaceName' peers",
        stdin: '$sudoPassword\n',
      );
      if (!listed.isSuccess) {
        throw StateError('could not list WireGuard peers');
      }
      final publicKeys = parseWireGuardPeerKeys(listed.stdout);
      final runner = PeerRevokeRunner(
        scriptSource: _ref.read(peerScriptSourceProvider),
      );
      for (final publicKey in publicKeys) {
        final network = installation.network;
        await runner.run(
          ssh: client,
          password: sudoPassword,
          interfaceName: installation.interfaceName,
          peerPublicKey: publicKey,
          installationId: network?.installationId,
          operationId: network == null ? null : const Uuid().v4(),
        );
      }
      for (final peer in localPeers) {
        await _ref.read(peerSecretRepositoryProvider).delete(peer.id);
        await _ref.read(peerRepositoryProvider).delete(peer.id);
      }
    } finally {
      await client.close();
    }
  }
}

/// Provides post-restore online operations.
final Provider<RestoreServerService> restoreServerServiceProvider =
    Provider<RestoreServerService>(RestoreServerService.new);
