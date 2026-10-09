import 'package:logger/logger.dart';

/// [LogOutput] that keeps every emitted line in memory for assertions.
class CapturingLogOutput extends LogOutput {
  /// Every line emitted through the logger, in order.
  final List<String> lines = [];

  @override
  void output(OutputEvent event) => lines.addAll(event.lines);
}

/// Builds a [Logger] that records plain, uncolored lines into [output].
Logger capturingLogger(CapturingLogOutput output) => Logger(
  level: Level.all,
  filter: ProductionFilter(),
  printer: SimplePrinter(colors: false),
  output: output,
);
