import 'package:fav/core/utils/equality.dart';
import 'package:fav/features/servers/domain/host_key_fingerprint.dart';
import 'package:fav/features/servers/domain/server_metadata.dart';
import 'package:fav/features/servers/domain/wireguard_installation.dart';
import 'package:meta/meta.dart';

/// A server registered in the app, with its credentials reference and the
/// metadata collected during provisioning.
///
/// The login password is never stored on a [Server]; it is requested on
/// demand for each operation (spec RF-20, §10).
@immutable
class Server {
  /// Creates a [Server].
  const Server({
    required this.id,
    required this.label,
    required this.host,
    required this.sshPort,
    required this.username,
    required this.createdAt,
    this.sshKeyId,
    this.metadata,
    this.pinnedHostKey,
    this.installation,
    this.lastSeenAt,
    this.userAuthorizedKeys = const [],
  });

  /// Local unique identifier (UUID).
  final String id;

  /// Human-readable name chosen by the user.
  final String label;

  /// IP address or hostname of the server.
  final String host;

  /// SSH port (default 22).
  final int sshPort;

  /// Username used for the SSH login.
  final String username;

  /// Reference to a generated SSH key in secure storage when hardening is
  /// enabled; `null` otherwise.
  final String? sshKeyId;

  /// System metadata collected by the probe; `null` before the first probe.
  final ServerMetadata? metadata;

  /// The pinned host key fingerprint (Trust On First Use); `null` until the
  /// first connection.
  final HostKeyFingerprint? pinnedHostKey;

  /// WireGuard installation details; `null` when not yet installed.
  final WireguardInstallation? installation;

  /// When the server was added to the list.
  final DateTime createdAt;

  /// When the server was last reached successfully; `null` if never.
  final DateTime? lastSeenAt;

  /// User-supplied SSH public keys deployed to the server's management account
  /// so the user keeps their own interactive access after hardening disables
  /// password login. Each entry is a normalized OpenSSH `authorized_keys` line
  /// (`SshPublicKey`); public material only, safe to persist in the encrypted
  /// local database.
  final List<String> userAuthorizedKeys;

  /// Whether subsequent SSH operations need to prompt the user for a
  /// password.
  ///
  /// Returns `false` when a stored SSH key is registered for this server —
  /// hardening installed an Ed25519 key in `authorized_keys`, so post-install
  /// operations (reprobe, resume, cleanup) authenticate with the key and the
  /// password prompt must be skipped (password auth is disabled server-side
  /// after hardening).
  bool get requiresPasswordForSsh => sshKeyId == null;

  /// Returns a copy of this server with the given fields replaced.
  ///
  /// TRAP: the nullable fields (`sshKeyId`, `installation`, …) cannot be
  /// CLEARED by passing null — that keeps the old value (deep-audit low
  /// nit; it has bitten the C1 and teardown fixes before). [clearSshKeyId]
  /// exists for the one caller that must drop a stale key claim; add a
  /// sibling flag only when a real caller needs it.
  Server copyWith({
    String? id,
    String? label,
    String? host,
    int? sshPort,
    String? username,
    String? sshKeyId,
    bool clearSshKeyId = false,
    ServerMetadata? metadata,
    HostKeyFingerprint? pinnedHostKey,
    WireguardInstallation? installation,
    DateTime? createdAt,
    DateTime? lastSeenAt,
    List<String>? userAuthorizedKeys,
  }) {
    return Server(
      id: id ?? this.id,
      label: label ?? this.label,
      host: host ?? this.host,
      sshPort: sshPort ?? this.sshPort,
      username: username ?? this.username,
      sshKeyId: clearSshKeyId ? null : (sshKeyId ?? this.sshKeyId),
      metadata: metadata ?? this.metadata,
      pinnedHostKey: pinnedHostKey ?? this.pinnedHostKey,
      installation: installation ?? this.installation,
      createdAt: createdAt ?? this.createdAt,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      userAuthorizedKeys: userAuthorizedKeys ?? this.userAuthorizedKeys,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is Server &&
        other.id == id &&
        other.label == label &&
        other.host == host &&
        other.sshPort == sshPort &&
        other.username == username &&
        other.sshKeyId == sshKeyId &&
        other.metadata == metadata &&
        other.pinnedHostKey == pinnedHostKey &&
        other.installation == installation &&
        other.createdAt == createdAt &&
        other.lastSeenAt == lastSeenAt &&
        listEquals(other.userAuthorizedKeys, userAuthorizedKeys);
  }

  @override
  int get hashCode {
    return Object.hash(
      id,
      label,
      host,
      sshPort,
      username,
      sshKeyId,
      metadata,
      pinnedHostKey,
      installation,
      createdAt,
      lastSeenAt,
      Object.hashAll(userAuthorizedKeys),
    );
  }
}
