import 'package:fav/core/crypto/ssh_public_key.dart';
import 'package:fav/core/errors/app_exception.dart';
import 'package:fav/features/install/application/ssh_auth_resolver.dart';
import 'package:fav/features/install/data/keys/ssh_key_repository.dart';
import 'package:fav/features/install/data/ssh/dart_ssh_client.dart';
import 'package:fav/features/install/domain/ssh_client.dart';
import 'package:fav/features/servers/data/hive_server_repository.dart';
import 'package:fav/features/servers/domain/server.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Deploys and removes user-supplied SSH public keys on an already-registered
/// server, over a live SSH session — the "later, at any time" path that
/// complements the install-time `26_deploy_user_keys` module.
///
/// Each key is written to the connecting (management) account's own
/// `~/.ssh/authorized_keys`, so no `sudo` is needed. The key line is fed to the
/// remote shell via stdin, never interpolated into the command, so its content
/// cannot break out of the snippet. Removal only ever touches the exact user
/// key line, never the app's own key (which is not part of
/// [Server.userAuthorizedKeys]), preserving the app's access.
class UserKeyService {
  /// Creates a [UserKeyService].
  const UserKeyService(this._ref);

  final Ref _ref;

  /// Appends [keyLines] (normalized OpenSSH `authorized_keys` lines) to the
  /// server's management account and records them on the [Server].
  ///
  /// [password] is required only when the server has no stored SSH key (see
  /// [SshAuthResolver]). Returns the updated, persisted [Server].
  Future<Server> addKeys({
    required Server server,
    required List<String> keyLines,
    String? password,
  }) async {
    // The app's own deployed key must never be tracked as a removable user key
    // — otherwise a later removal would revoke the app's access and, once
    // hardening disabled password login, lock the user out (anti-lockout,
    // spec §10.2). Compare by fingerprint so a different comment cannot slip it
    // past.
    final appFingerprint = await _appKeyFingerprint(server);
    final fresh = <String>[];
    for (final line in keyLines) {
      // Re-validate (parity with `26_deploy_user_keys`): only well-formed,
      // accepted key lines are ever written to authorized_keys, regardless of
      // what reached this list.
      final parsed = SshPublicKey.tryParse(line);
      if (parsed == null) {
        continue;
      }
      if (server.userAuthorizedKeys.contains(parsed.line)) {
        continue;
      }
      if (appFingerprint != null && parsed.fingerprint == appFingerprint) {
        continue;
      }
      fresh.add(parsed.line);
    }
    if (fresh.isEmpty) {
      return server;
    }
    await _withConnection(server, password, (ssh) async {
      for (final key in fresh) {
        final result = await ssh.run(_appendSnippet, stdin: key);
        if (!result.isSuccess) {
          throw const AppException(ErrorCode.sshKeyDeployFailed);
        }
      }
    });
    return _persist(
      server,
      [...server.userAuthorizedKeys, ...fresh],
    );
  }

  /// Removes [keyLine] from the server's management account and from the
  /// [Server] record. Succeeds even if the key was already absent server-side.
  Future<Server> removeKey({
    required Server server,
    required String keyLine,
    String? password,
  }) async {
    // Only act on keys the app actually tracks for this server; never open an
    // SSH session to rewrite authorized_keys for an untracked line.
    if (!server.userAuthorizedKeys.contains(keyLine)) {
      return server;
    }
    await _withConnection(server, password, (ssh) async {
      final result = await ssh.run(_removeSnippet, stdin: keyLine);
      if (!result.isSuccess) {
        throw const AppException(ErrorCode.sshKeyDeployFailed);
      }
    });
    return _persist(
      server,
      server.userAuthorizedKeys.where((k) => k != keyLine).toList(),
    );
  }

  Future<void> _withConnection(
    Server server,
    String? password,
    Future<void> Function(SshClient ssh) body,
  ) async {
    final params = await _ref
        .read(sshAuthResolverProvider)
        .resolve(server: server, password: password);
    final ssh = _ref.read(sshClientFactoryProvider)();
    await ssh.connect(params);
    try {
      await body(ssh);
    } finally {
      await ssh.close();
    }
  }

  /// Returns the SHA-256 fingerprint of the app's deployed Ed25519 key for
  /// [server], or `null` when no app key is registered or it is unavailable.
  Future<String?> _appKeyFingerprint(Server server) async {
    final keyId = server.sshKeyId;
    if (keyId == null) {
      return null;
    }
    final pair = await _ref.read(sshKeyRepositoryProvider).get(keyId);
    if (pair == null) {
      return null;
    }
    // The comment does not affect the fingerprint, which is computed over the
    // key blob only.
    return SshPublicKey.tryParse(
      pair.authorizedKeysEntry(comment: 'fav'),
    )?.fingerprint;
  }

  Future<Server> _persist(Server server, List<String> keys) async {
    final updated = server.copyWith(
      userAuthorizedKeys: keys,
      lastSeenAt: DateTime.now(),
    );
    await _ref.read(serverRepositoryProvider).save(updated);
    return updated;
  }

  /// Appends the key read from stdin to the connecting user's authorized_keys,
  /// idempotently, creating `.ssh/` with the modes sshd requires. Raw strings:
  /// `$HOME`/`$key` are shell variables and `\n` is a printf escape, none of
  /// them Dart interpolation.
  static const String _appendSnippet =
      r'umask 077; cd "$HOME" || exit 1; '
      'mkdir -p .ssh && chmod 700 .ssh; '
      'touch .ssh/authorized_keys && chmod 600 .ssh/authorized_keys; '
      r'key="$(cat)"; '
      r'grep -qxF -- "$key" .ssh/authorized_keys '
      r'|| printf "%s\n" "$key" >> .ssh/authorized_keys';

  /// Removes the exact key read from stdin from authorized_keys, leaving any
  /// other entry (such as the app's own key) untouched.
  static const String _removeSnippet =
      r'cd "$HOME" || exit 1; f=.ssh/authorized_keys; '
      r'[ -f "$f" ] || exit 0; '
      r'key="$(cat)"; tmp="$(mktemp)"; '
      r'grep -vxF -- "$key" "$f" > "$tmp" || true; '
      r'cat "$tmp" > "$f"; rm -f "$tmp"; chmod 600 "$f"';
}

/// Provides the [UserKeyService].
final Provider<UserKeyService> userKeyServiceProvider =
    Provider<UserKeyService>(UserKeyService.new);
