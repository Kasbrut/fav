import 'dart:typed_data';

/// A live interactive SSH shell (PTY) session.
///
/// Returned by `SshClient.startShell`. Unlike one-shot commands, the session
/// stays open for as long as the user keeps the terminal on screen; the owner
/// must call [close] when done (and close the originating `SshClient`
/// afterwards). Output is exposed as raw bytes — the presentation layer decodes
/// it (streaming UTF-8) so multi-byte sequences split across packets survive.
abstract interface class SshShellSession {
  /// Merged stdout and stderr of the remote PTY, as raw bytes.
  Stream<Uint8List> get output;

  /// Writes [data] (typically UTF-8 keystrokes) to the remote PTY stdin.
  void write(Uint8List data);

  /// Informs the remote PTY of a new terminal size, in character cells.
  void resize(int columns, int rows);

  /// Completes when the session ends — remote close, disconnect, or [close].
  Future<void> get done;

  /// Closes the session and frees its channel.
  Future<void> close();
}
