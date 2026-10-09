import 'package:fav/features/install/domain/ssh_client.dart';
import 'package:fav/features/install/domain/ssh_shell_session.dart';

import 'fake_ssh_shell_session.dart';

/// Fake [SshClient] for tests: [run] replays canned stdout keyed by command.
class FakeSshClient implements SshClient {
  /// Creates a [FakeSshClient] that answers commands from [responses].
  ///
  /// [connectError] / [startShellError], when set, are thrown by the matching
  /// method to drive failure paths. [shellSession] is returned by [startShell]
  /// (a fresh [FakeSshShellSession] by default).
  FakeSshClient(
    this.responses, {
    this.connectError,
    this.startShellError,
    FakeSshShellSession? shellSession,
  }) : shellSession = shellSession ?? FakeSshShellSession();

  /// Canned stdout keyed by the exact command string.
  final Map<String, String> responses;

  /// Error thrown by [connect]; `null` means it succeeds.
  final Exception? connectError;

  /// Error thrown by [startShell]; `null` means it succeeds.
  final Exception? startShellError;

  /// Session returned by [startShell].
  final FakeSshShellSession shellSession;

  /// Number of times [connect] was called.
  int connectCount = 0;

  /// Number of times [close] was called.
  int closeCount = 0;

  @override
  Future<SshCommandResult> run(String command, {String? stdin}) async {
    final known = responses.containsKey(command);
    return SshCommandResult(
      stdout: responses[command] ?? '',
      stderr: '',
      exitCode: known ? 0 : 1,
    );
  }

  @override
  Future<void> connect(SshConnectionParams params) async {
    connectCount++;
    final error = connectError;
    if (error != null) throw error;
  }

  @override
  Future<void> uploadBytes({
    required String remotePath,
    required List<int> data,
  }) async {}

  @override
  Future<SshShellSession> startShell({int columns = 80, int rows = 24}) async {
    final error = startShellError;
    if (error != null) throw error;
    return shellSession;
  }

  @override
  Future<void> close() async {
    closeCount++;
  }
}
