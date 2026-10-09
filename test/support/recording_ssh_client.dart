import 'dart:async';

import 'package:fav/features/install/domain/ssh_client.dart';
import 'package:fav/features/install/domain/ssh_shell_session.dart';

/// A recorded SFTP upload.
class RecordedUpload {
  /// Creates a [RecordedUpload].
  RecordedUpload({required this.remotePath, required this.data});

  /// The remote destination path.
  final String remotePath;

  /// The bytes that were uploaded.
  final List<int> data;
}

/// [SshClient] test double that records every command and upload.
///
/// [onRun] decides each command's result and may throw to simulate a
/// connection failure; [onConnect] may throw to simulate a connect failure.
class RecordingSshClient implements SshClient {
  /// Creates a [RecordingSshClient].
  RecordingSshClient({this.onRun, this.onConnect, this.onUpload});

  /// Produces the result for a command; may throw to fail the call.
  final FutureOr<SshCommandResult> Function(String command)? onRun;

  /// Invoked by [connect]; may throw to fail the connection.
  final void Function()? onConnect;

  /// Invoked by [uploadBytes]; may throw to simulate an interrupted upload.
  final void Function(String remotePath)? onUpload;

  /// Every command passed to [run], in order.
  final List<String> runCommands = [];

  /// The `stdin` passed to each [run] call, aligned with [runCommands].
  final List<String?> runStdins = [];

  /// Every upload passed to [uploadBytes], in order.
  final List<RecordedUpload> uploads = [];

  /// Number of times [connect] was called.
  int connectCount = 0;

  /// Number of times [close] was called.
  int closeCount = 0;

  @override
  Future<void> connect(SshConnectionParams params) async {
    connectCount++;
    onConnect?.call();
  }

  @override
  Future<SshCommandResult> run(String command, {String? stdin}) async {
    runCommands.add(command);
    runStdins.add(stdin);
    final handler = onRun;
    if (handler == null) {
      return const SshCommandResult(stdout: '', stderr: '', exitCode: 0);
    }
    return handler(command);
  }

  @override
  Future<void> uploadBytes({
    required String remotePath,
    required List<int> data,
  }) async {
    onUpload?.call(remotePath);
    uploads.add(RecordedUpload(remotePath: remotePath, data: List.of(data)));
  }

  @override
  Future<SshShellSession> startShell({int columns = 80, int rows = 24}) async {
    throw UnimplementedError('RecordingSshClient does not support shells');
  }

  @override
  Future<void> close() async {
    closeCount++;
  }
}
