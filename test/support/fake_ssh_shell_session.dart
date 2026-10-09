import 'dart:async';
import 'dart:typed_data';

import 'package:fav/features/install/domain/ssh_shell_session.dart';

/// Controllable [SshShellSession] fake for tests.
///
/// Push remote output with [emit], end the session with [endRemote], and
/// assert on the recorded [writes] and [resizes].
class FakeSshShellSession implements SshShellSession {
  final StreamController<Uint8List> _output =
      StreamController<Uint8List>.broadcast();
  final Completer<void> _done = Completer<void>();

  /// Every payload written to the remote PTY stdin, in order.
  final List<Uint8List> writes = [];

  /// Every resize request, as (columns, rows) pairs.
  final List<({int columns, int rows})> resizes = [];

  /// Whether [close] was called.
  bool closed = false;

  /// Emits [data] as remote output.
  void emit(List<int> data) {
    if (!_output.isClosed) _output.add(Uint8List.fromList(data));
  }

  /// Simulates the remote side ending the session.
  void endRemote() {
    if (!_done.isCompleted) _done.complete();
    if (!_output.isClosed) unawaited(_output.close());
  }

  @override
  Stream<Uint8List> get output => _output.stream;

  @override
  void write(Uint8List data) => writes.add(data);

  @override
  void resize(int columns, int rows) =>
      resizes.add((columns: columns, rows: rows));

  @override
  Future<void> get done => _done.future;

  @override
  Future<void> close() async {
    closed = true;
    if (!_done.isCompleted) _done.complete();
    if (!_output.isClosed) await _output.close();
  }
}
