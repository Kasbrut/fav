import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:fav/core/errors/app_exception.dart';
import 'package:fav/core/utils/app_logger.dart';
import 'package:fav/features/install/data/ssh/host_key_change_registry.dart';
import 'package:fav/features/install/data/ssh/host_key_store.dart';
import 'package:fav/features/install/data/ssh/ssh_error_mapper.dart';
import 'package:fav/features/install/domain/ssh_client.dart';
import 'package:fav/features/install/domain/ssh_shell_session.dart';
import 'package:fav/features/servers/domain/host_key_fingerprint.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';

/// Renders one executed command as a log line: the command, exit code and
/// output byte counts. By construction it takes neither the stdin payload
/// (it carries `sudo -S` passwords and `config.env`) nor the output contents
/// (`client.conf` reads carry key material) — only their sizes.
String describeExec(
  String command,
  SshCommandResult result, {
  bool withStdin = false,
}) {
  return 'SSH exec${withStdin ? ' (with stdin)' : ''}: $command → '
      'exit ${result.exitCode} '
      '(stdout ${result.stdout.length} B, stderr ${result.stderr.length} B)';
}

/// Timeout for the initial SSH handshake (spec §3.3).
const Duration _connectTimeout = Duration(seconds: 15);

/// Timeout for a single command run with a stdin payload (spec §3.3).
///
/// Bounds the privileged `sudo -S` path so a stalled remote process cannot
/// hang the anti-lockout flow indefinitely.
const Duration _commandTimeout = Duration(seconds: 60);

/// [SshClient] backed by `dartssh2`, with Trust-On-First-Use host key pinning.
///
/// Debug tracing (§10.1-safe): commands, exit codes and byte counts are
/// logged; stdin payloads and stream contents never are — stdin carries
/// `sudo -S` passwords and stdout can carry key material (`client.conf`).
class DartSshClient implements SshClient {
  /// Creates a [DartSshClient] that pins host keys via the given store.
  DartSshClient(
    this._hostKeyStore, {
    Logger? logger,
    this._onHostKeyMismatch,
  }) : _logger = logger ?? appLogger;

  final HostKeyStore _hostKeyStore;
  final Logger _logger;
  final void Function(HostKeyFingerprint)? _onHostKeyMismatch;

  SSHClient? _client;

  @override
  Future<void> connect(SshConnectionParams params) async {
    _logger.d(
      'SSH connect: ${params.username}@${params.host}:${params.port} '
      '(auth: ${params.identities?.isNotEmpty ?? false ? 'key' : 'password'}'
      '${params.passwordAuthAllowed ? '' : ', password fallback disabled'})',
    );
    final SSHSocket socket;
    try {
      socket = await SSHSocket.connect(
        params.host.startsWith('[') && params.host.endsWith(']')
            ? params.host.substring(1, params.host.length - 1)
            : params.host,
        params.port,
        timeout: _connectTimeout,
      );
    } on Object catch (error) {
      _logger.w(
        'SSH connect to ${params.host}:${params.port} failed: '
        '${error.runtimeType}',
      );
      throw AppException(
        mapSshError(error),
        cause: error.runtimeType.toString(),
      );
    }

    HostKeyFingerprint? unknownKey;
    HostKeyFingerprint? mismatchedKey;
    var legacyRepin = false;
    var mismatch = false;

    final client = SSHClient(
      socket,
      username: params.username,
      // dartssh2 4.x defaults exclude the legacy SHA-1/CBC algorithms. Keep
      // the MAC policy explicit so a future library default cannot weaken it.
      algorithms: const SSHAlgorithms(
        mac: [
          SSHMacType.hmacSha256Etm,
          SSHMacType.hmacSha512Etm,
          SSHMacType.hmacSha256,
          SSHMacType.hmacSha512,
        ],
      ),
      // When the caller forbids password fallback (hardening flow,
      // spec §10.3) we must not register an onPasswordRequest — dartssh2
      // would otherwise try password auth and a successful "key" connect
      // could in fact be a silent password fallback, masking a broken
      // authorized_keys before we disable password authentication.
      identities: params.identities,
      onPasswordRequest: params.passwordAuthAllowed
          ? () => params.password
          : null,
      onVerifyHostKey: (type, fingerprintBytes) async {
        // All decision logic lives in verifyReceivedHostKey so every arm is
        // unit-tested (migration audit L4); this closure only applies the
        // side effects the connect error path reads after the handshake.
        final pinned = await _hostKeyStore.lookup(params.host, params.port);
        final verification = verifyReceivedHostKey(
          host: params.host,
          port: params.port,
          keyType: type,
          fingerprintBytes: fingerprintBytes,
          pinned: pinned,
          logger: _logger,
        );
        if (verification.mismatch) {
          mismatch = true;
          mismatchedKey = verification.mismatchedKey;
        }
        final pending = verification.pendingKey;
        if (pending != null) {
          unknownKey = pending;
          legacyRepin = verification.previouslyTrusted;
        }
        return verification.accept;
      },
    );

    try {
      // Bounded: a server that completes the TCP handshake but stalls the
      // key exchange must not hold the connect (and any password snapshot a
      // fire-and-forget caller keeps alive) forever (review L1).
      await client.authenticated.timeout(_connectTimeout);
    } on Object catch (error) {
      unawaited(client.close());
      if (mismatch) {
        final received = mismatchedKey;
        if (received != null) {
          _onHostKeyMismatch?.call(received);
          throw HostKeyMismatchException(received);
        }
        throw const AppException(ErrorCode.hostKeyMismatch);
      }
      final pending = unknownKey;
      if (pending != null) {
        throw HostKeyUnknownException(pending, previouslyTrusted: legacyRepin);
      }
      throw AppException(
        mapSshError(error),
        cause: error.runtimeType.toString(),
      );
    }

    // Outside the try: a throwing logger must never turn a successful
    // authentication into a mapped connection error.
    _logger.d('SSH authenticated: ${params.username}@${params.host}');
    _client = client;
  }

  @override
  Future<SshCommandResult> run(String command, {String? stdin}) async {
    final client = _requireClient();
    if (stdin == null) {
      // Bound the stdin-less path too: a black-holed connection (silent network
      // switch / NAT drop) would otherwise leave this await pending forever —
      // the poll read for a root login is stdin-less (audit H5).
      final result = await client
          .runWithResult(command)
          .timeout(_commandTimeout);
      final mapped = SshCommandResult(
        stdout: utf8.decode(result.stdout, allowMalformed: true),
        stderr: utf8.decode(result.stderr, allowMalformed: true),
        exitCode: result.exitCode ?? -1,
      );
      _logExec(command, mapped);
      return mapped;
    }
    final result = await _runWithStdin(client, command, stdin);
    _logExec(command, result, withStdin: true);
    return result;
  }

  /// Last emitted exec trace; the 2.5 s poll repeats an identical command
  /// with an identical result, and repeating the line would bury everything
  /// else in the log.
  String? _lastExecLog;

  void _logExec(
    String command,
    SshCommandResult result, {
    bool withStdin = false,
  }) {
    final line = describeExec(command, result, withStdin: withStdin);
    if (line == _lastExecLog) return;
    _lastExecLog = line;
    _logger.d(line);
  }

  /// Runs [command] feeding [stdin] to its standard input over a session.
  Future<SshCommandResult> _runWithStdin(
    SSHClient client,
    String command,
    String stdin,
  ) async {
    // Bounded like the stream drain below: the channel open itself can hang
    // on a black-holed connection (review L1).
    final session = await client.execute(command).timeout(_commandTimeout);
    session.stdin.add(utf8.encode(stdin));
    await session.stdin.close();
    final out = <int>[];
    final err = <int>[];
    await Future.wait<void>([
      session.stdout.forEach(out.addAll),
      session.stderr.forEach(err.addAll),
      session.done,
    ]).timeout(_commandTimeout);
    return SshCommandResult(
      stdout: utf8.decode(out, allowMalformed: true),
      stderr: utf8.decode(err, allowMalformed: true),
      exitCode: session.exitCode ?? -1,
    );
  }

  @override
  Future<void> uploadBytes({
    required String remotePath,
    required List<int> data,
  }) async {
    // We deliberately do NOT use SFTP here: `dartssh2 2.17.1` opens the SFTP
    // subsystem channel against OpenSSH ≥ 10 servers and the server replies
    // with SSH_OPEN_CONNECT_FAILED (M14 smoke test 2026-05-20). Plain exec
    // channels work fine, so we stream the payload base64-encoded over
    // stdin and decode it server-side. `umask 077` makes the file 0600 from
    // creation, so the upload of `config.env` (which carries the new-user
    // password) is never briefly world-readable.
    final encoded = base64.encode(data);
    final result = await _runWithStdin(
      _requireClient(),
      "umask 077 && base64 -d > '$remotePath'",
      encoded,
    );
    // config.env has a fixed, known key set: its byte count would disclose
    // the new-user password length by subtraction, so withhold it.
    final size = remotePath.endsWith('config.env')
        ? 'size withheld'
        : '${data.length} B';
    _logger.d('SSH upload: $remotePath ($size) → exit ${result.exitCode}');
    if (result.exitCode != 0) {
      throw StateError(
        'Upload to $remotePath failed '
        '(exit ${result.exitCode}): ${result.stderr.trim()}',
      );
    }
  }

  @override
  Future<SshShellSession> startShell({int columns = 80, int rows = 24}) async {
    final session = await _requireClient().shell(
      pty: SSHPtyConfig(width: columns, height: rows),
    );
    return _DartSshShellSession(session);
  }

  @override
  Future<void> close() async {
    await _client?.close();
    _client = null;
  }

  SSHClient _requireClient() {
    final client = _client;
    if (client == null) {
      throw StateError('SshClient.connect must be called before use');
    }
    return client;
  }
}

/// [SshShellSession] backed by a `dartssh2` [SSHSession] PTY.
///
/// Merges the remote stdout and stderr into a single byte stream and forwards
/// keystrokes and resize events back to the session. Owns the session/channel
/// only — the originating [DartSshClient] still owns the connection.
class _DartSshShellSession implements SshShellSession {
  _DartSshShellSession(this._session) {
    _stdoutSub = _session.stdout.listen(
      _output.add,
      onError: _output.addError,
    );
    _stderrSub = _session.stderr.listen(
      _output.add,
      onError: _output.addError,
    );
    // Close the output stream once the remote process is gone, so listeners
    // see the session end.
    unawaited(_session.done.whenComplete(_output.close));
  }

  final SSHSession _session;
  final StreamController<Uint8List> _output =
      StreamController<Uint8List>.broadcast();
  StreamSubscription<Uint8List>? _stdoutSub;
  StreamSubscription<Uint8List>? _stderrSub;

  @override
  Stream<Uint8List> get output => _output.stream;

  @override
  void write(Uint8List data) => _session.write(data);

  @override
  void resize(int columns, int rows) => _session.resizeTerminal(columns, rows);

  @override
  Future<void> get done => _session.done;

  @override
  Future<void> close() async {
    await _stdoutSub?.cancel();
    await _stderrSub?.cancel();
    _session.close();
    if (!_output.isClosed) {
      await _output.close();
    }
  }
}

/// Provides a factory for fresh, unconnected [SshClient] instances.
final Provider<SshClient Function()> sshClientFactoryProvider =
    Provider<SshClient Function()>((ref) {
      final hostKeyStore = ref.watch(hostKeyStoreProvider);
      final logger = ref.watch(loggerProvider);
      final changes = ref.read(hostKeyChangeRegistryProvider.notifier);
      return () => DartSshClient(
        hostKeyStore,
        logger: logger,
        onHostKeyMismatch: changes.record,
      );
    });
