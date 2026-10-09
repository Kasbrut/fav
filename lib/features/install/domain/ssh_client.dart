import 'package:dartssh2/dartssh2.dart' show SSHKeyPair;
import 'package:fav/core/errors/app_exception.dart';
import 'package:fav/features/install/domain/ssh_shell_session.dart';
import 'package:fav/features/servers/domain/host_key_fingerprint.dart';
import 'package:meta/meta.dart';

/// Parameters needed to open an SSH connection.
///
/// [password] is held only in memory for the operation; it must never be
/// persisted or logged. [identities], when present, lets the client attempt
/// public-key authentication — used by the optional hardening flow
/// (spec §10.3) to verify that the new user's Ed25519 key works before any
/// `PasswordAuthentication no` change is applied.
@immutable
class SshConnectionParams {
  /// Creates an [SshConnectionParams].
  const SshConnectionParams({
    required this.host,
    required this.port,
    required this.username,
    required this.password,
    this.identities,
    this.passwordAuthAllowed = true,
  });

  /// IP address or hostname of the server.
  final String host;

  /// SSH port.
  final int port;

  /// Login username.
  final String username;

  /// Login password — never persisted, never logged.
  final String password;

  /// Optional list of key pairs to try for public-key authentication.
  ///
  /// Never logged or stringified: see [toString].
  final List<SSHKeyPair>? identities;

  /// Whether password authentication is allowed as a fallback.
  ///
  /// When `false`, only [identities] may authenticate the connection — used
  /// by the hardening flow to *prove* key-based login works (spec §10.3),
  /// rather than tolerate a silent password fallback that would mask a
  /// broken `authorized_keys`.
  final bool passwordAuthAllowed;

  @override
  String toString() {
    final identitiesPart = identities == null
        ? 'none'
        : '<${identities!.length} key(s), redacted>';
    return 'SshConnectionParams(host: $host, port: $port, '
        'username: $username, password: <redacted>, '
        'identities: $identitiesPart, '
        'passwordAuthAllowed: $passwordAuthAllowed)';
  }
}

/// Result of running a single command over SSH.
@immutable
class SshCommandResult {
  /// Creates an [SshCommandResult].
  const SshCommandResult({
    required this.stdout,
    required this.stderr,
    required this.exitCode,
  });

  /// Captured standard output.
  final String stdout;

  /// Captured standard error.
  final String stderr;

  /// Process exit code (`-1` when the remote side reported none).
  final int exitCode;

  /// Whether the command finished successfully (exit code `0`).
  bool get isSuccess => exitCode == 0;
}

/// An SSH connection to a server: connect, run commands, upload files, close.
///
/// An instance represents a single connection. [run] and [uploadBytes] must
/// be called only after [connect] has completed.
abstract interface class SshClient {
  /// Connects and authenticates with [params].
  ///
  /// Throws [HostKeyUnknownException] when the server's host key has never
  /// been pinned, and an `AppException` for connection, authentication or
  /// host-key-mismatch failures.
  Future<void> connect(SshConnectionParams params);

  /// Runs [command] on the connected server.
  ///
  /// When [stdin] is given, its UTF-8 bytes are written to the command's
  /// standard input — used to feed a password to `sudo -S` so it never
  /// appears on the command line or in the process list.
  Future<SshCommandResult> run(String command, {String? stdin});

  /// Uploads [data] to [remotePath] over SFTP, creating or truncating it.
  Future<void> uploadBytes({
    required String remotePath,
    required List<int> data,
  });

  /// Starts an interactive PTY shell on the connected server.
  ///
  /// The connection must stay open for the returned session's lifetime; close
  /// this client only after the session is done. [columns] and [rows] set the
  /// initial terminal size.
  Future<SshShellSession> startShell({int columns = 80, int rows = 24});

  /// Closes the connection and frees its resources.
  Future<void> close();
}

/// Thrown by [SshClient.connect] when the server's host key has never been
/// pinned, so the user must confirm it (Trust On First Use, spec §10).
class HostKeyUnknownException implements Exception {
  /// Creates a [HostKeyUnknownException] for the unverified [fingerprint].
  HostKeyUnknownException(this.fingerprint, {this.previouslyTrusted = false});

  /// The fingerprint of the still-untrusted host key, to show to the user.
  final HostKeyFingerprint fingerprint;

  /// True when a pin exists but was stored under a legacy hash algorithm
  /// and cannot be compared (the MD5 → SHA-256 migration): the
  /// re-confirmation dialog must say the server was trusted before, not
  /// claim a first connection (security audit M1).
  final bool previouslyTrusted;

  @override
  String toString() => 'HostKeyUnknownException(${fingerprint.host})';
}

/// A pinned host key changed. The received key is exposed only so an explicit
/// replacement flow can show both fingerprints for out-of-band verification;
/// ordinary SSH operations still fail closed with [ErrorCode.hostKeyMismatch].
class HostKeyMismatchException extends AppException {
  /// Creates a mismatch carrying the untrusted [received] fingerprint.
  HostKeyMismatchException(this.received) : super(ErrorCode.hostKeyMismatch);

  /// The new, still-untrusted fingerprint received during the handshake.
  final HostKeyFingerprint received;
}
