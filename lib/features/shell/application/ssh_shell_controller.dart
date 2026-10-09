import 'dart:async';

import 'package:fav/core/errors/app_exception.dart';
import 'package:fav/core/utils/app_logger.dart';
import 'package:fav/features/install/application/ssh_auth_resolver.dart';
import 'package:fav/features/install/data/ssh/dart_ssh_client.dart';
import 'package:fav/features/install/data/ssh/ssh_error_mapper.dart';
import 'package:fav/features/install/domain/ssh_client.dart';
import 'package:fav/features/install/domain/ssh_shell_session.dart';
import 'package:fav/features/servers/data/hive_server_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:meta/meta.dart';

/// State of an interactive SSH shell screen.
@immutable
sealed class SshShellState {
  const SshShellState();
}

/// The connection is being opened (socket + auth + shell allocation).
class SshShellConnecting extends SshShellState {
  /// Creates a [SshShellConnecting].
  const SshShellConnecting();
}

/// The shell is live; [session] streams output and accepts input.
class SshShellConnected extends SshShellState {
  /// Creates a [SshShellConnected] around the live [session].
  const SshShellConnected(this.session);

  /// The live shell session the terminal view is wired to.
  final SshShellSession session;
}

/// The connection failed; [code] maps to the help catalogue (`ERR-xx`).
class SshShellError extends SshShellState {
  /// Creates a [SshShellError] for [code].
  const SshShellError(this.code);

  /// The mapped error code, surfaced with a human message + help link.
  final ErrorCode code;
}

/// The session ended (remote close, disconnect, or local close).
class SshShellClosed extends SshShellState {
  /// Creates a [SshShellClosed].
  const SshShellClosed();
}

/// Owns the lifecycle of one interactive SSH shell, keyed by `serverId`.
///
/// Reuses the shared SSH machinery — [SshAuthResolver] for key-vs-password
/// auth and [SshClient.connect] for the socket, authentication and host-key
/// Trust-On-First-Use checks — so a shell connection behaves exactly like
/// every other SSH operation. Unlike one-shot commands, the connection is kept
/// open for the screen's lifetime and torn down on dispose (back-navigation).
class SshShellController extends Notifier<SshShellState> {
  /// Creates a controller for the server identified by [arg].
  SshShellController(this.arg);

  /// The server id this controller is scoped to (family argument).
  final String arg;

  SshClient? _client;
  SshShellSession? _session;
  // Held only in memory for this screen's lifetime so [retry] can reconnect
  // without re-prompting; wiped on dispose. Never persisted, never logged.
  String? _password;
  bool _disposed = false;
  bool _starting = false;

  @override
  SshShellState build() {
    ref.onDispose(_teardown);
    return const SshShellConnecting();
  }

  /// Opens the connection and shell. [password] is required for password-auth
  /// servers and ignored for key-hardened ones (resolved by [SshAuthResolver]).
  Future<void> start({String? password}) async {
    if (_disposed || _starting) {
      return;
    }
    _starting = true;
    _password = password;
    if (state is! SshShellConnecting) {
      state = const SshShellConnecting();
    }
    try {
      final server = await ref.read(serverRepositoryProvider).getById(arg);
      if (server == null) {
        _fail(const AppException(ErrorCode.connHostUnreachable));
        return;
      }
      final params = await ref
          .read(sshAuthResolverProvider)
          .resolve(server: server, password: password);
      final client = ref.read(sshClientFactoryProvider)();
      _client = client;
      await client.connect(params);
      final session = await client.startShell();
      if (_disposed) {
        await session.close();
        await client.close();
        return;
      }
      _session = session;
      state = SshShellConnected(session);
      // Surface remote-side or transport closure as a terminal "Disconnected"
      // state so the user can reconnect.
      unawaited(
        session.done.whenComplete(() {
          if (_disposed) {
            return;
          }
          if (state is SshShellConnected) {
            state = const SshShellClosed();
          }
          // The remote side (or transport) closed the session: release the now
          // dead client socket instead of holding it until retry/dispose
          // (audit L1-shell).
          unawaited(_disposeSession());
        }),
      );
    } on HostKeyUnknownException {
      // Defensive: the host key is pinned at add-time, so this should not
      // happen here. Treat it as a trust problem to be resolved by re-probing
      // the server, not by re-running Trust-On-First-Use inside the shell.
      await _disposeSession();
      _fail(const AppException(ErrorCode.hostKeyMismatch));
    } on AppException catch (error) {
      await _disposeSession();
      _fail(error);
    } on Object catch (error) {
      // Log type only — the error may carry remote stderr.
      appLogger.w('SSH shell failed: ${error.runtimeType}');
      await _disposeSession();
      _fail(AppException(mapSshError(error)));
    } finally {
      _starting = false;
    }
  }

  /// Reconnects after a failure or disconnect, reusing the in-memory password.
  Future<void> retry() async {
    if (_disposed) {
      return;
    }
    await _disposeSession();
    state = const SshShellConnecting();
    await start(password: _password);
  }

  /// Forwards a terminal resize to the live session (no-op when not connected).
  void resize(int columns, int rows) {
    if (state is SshShellConnected) {
      _session?.resize(columns, rows);
    }
  }

  void _fail(AppException error) {
    if (_disposed) {
      return;
    }
    // Code only: no error reaching this path carries a detail today, and a
    // future one could carry raw remote stderr — don't log it by default.
    ref.read(loggerProvider).w('SSH shell failed: ${error.code.name}');
    state = SshShellError(error.code);
  }

  Future<void> _disposeSession() async {
    final session = _session;
    final client = _client;
    _session = null;
    _client = null;
    await session?.close();
    await client?.close();
  }

  void _teardown() {
    _disposed = true;
    _password = null;
    unawaited(_disposeSession());
  }
}

/// Provides the SSH shell controller per server id.
final NotifierProviderFamily<SshShellController, SshShellState, String>
sshShellControllerProvider = NotifierProvider.autoDispose
    .family<SshShellController, SshShellState, String>(SshShellController.new);
