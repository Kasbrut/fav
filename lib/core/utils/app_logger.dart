import 'dart:collection';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';

/// Matches `secretKey: value` / `secretKey=value` pairs in a log line.
final RegExp _secretAssignment = RegExp(
  r'(password|passwd|secret|private[_\s]?key|psk|preshared[_\s]?key|token)'
  r'(\s*[:=]\s*)(\S+)',
  caseSensitive: false,
);

/// Replaces likely secret values in [line] with a redaction marker.
///
/// Defense in depth (spec §10.1): the primary rule is that callers never pass
/// secrets to the logger; this scrubs the obvious cases that slip through.
String redactSecrets(String line) {
  if (line.contains('PRIVATE KEY')) {
    return '<redacted: private key material>';
  }
  return line.replaceAllMapped(
    _secretAssignment,
    (match) => '${match.group(1)}${match.group(2)}<redacted>',
  );
}

/// Redacts a *sequence* of lines, suppressing everything inside a
/// `BEGIN … PRIVATE KEY` / `END … PRIVATE KEY` block — [redactSecrets] is
/// per-line, so a block's base64 body would otherwise survive (security
/// audit M3 on the log-attachment feature). Lines outside a block go
/// through [redactSecrets] as usual.
List<String> redactSecretLines(Iterable<String> lines) {
  final out = <String>[];
  var inPemBlock = false;
  for (final line in lines) {
    if (inPemBlock) {
      if (line.contains('PRIVATE KEY') && line.contains('END')) {
        inPemBlock = false;
      }
      continue;
    }
    if (line.contains('PRIVATE KEY')) {
      out.add('<redacted: private key material>');
      inPemBlock = line.contains('BEGIN');
      continue;
    }
    out.add(redactSecrets(line));
  }
  return out;
}

/// A [LogPrinter] that redacts likely secrets from another printer's output.
class RedactingLogPrinter extends LogPrinter {
  /// Creates a [RedactingLogPrinter] wrapping the given base printer.
  RedactingLogPrinter(this._base);

  final LogPrinter _base;

  @override
  List<String> log(LogEvent event) {
    return _base.log(event).map(redactSecrets).toList();
  }
}

/// In-memory ring buffer of recent log lines (bug-report attachments).
///
/// RAM only — never persisted to disk. Lines are stored plain (timestamp,
/// level, message — no ANSI/pretty decoration) and are run through
/// [redactSecrets] before entering the buffer, so a raw secret can never sit
/// in memory awaiting export. The buffer feeds the "attach recent app logs"
/// flow of the bug report, which additionally scrubs identifying values
/// (IPs, hosts, usernames) and previews the result before anything leaves
/// the device.
class AppLogBuffer extends LogOutput {
  /// Creates a buffer holding at most [capacity] lines.
  AppLogBuffer({this.capacity = 300});

  /// Maximum number of retained lines; the oldest are dropped first.
  final int capacity;

  final ListQueue<String> _lines = ListQueue<String>();

  /// The buffered lines, oldest first.
  List<String> get lines => List.unmodifiable(_lines);

  @override
  void output(OutputEvent event) {
    final origin = event.origin;
    final stamp = origin.time.toIso8601String();
    final level = origin.level.name.toUpperCase();
    // Block-aware redaction: a multi-line message carrying a PEM block must
    // not leak its base64 body line by line (audit M3).
    final redacted = redactSecretLines(origin.message.toString().split('\n'));
    for (final line in redacted) {
      _add('[$stamp] $level $line');
    }
    // Error objects can carry raw remote output: type only, like the
    // logging call sites themselves do.
    final error = origin.error;
    if (error != null) {
      _add('[$stamp] $level error: ${error.runtimeType}');
    }
  }

  /// Drops every buffered line — called by the local-data wipe so the
  /// erased servers' hosts and usernames do not linger in an exportable
  /// buffer (security audit M4).
  void clear() => _lines.clear();

  void _add(String line) {
    if (_lines.length >= capacity) {
      _lines.removeFirst();
    }
    _lines.add(line);
  }
}

/// The global ring buffer behind [appLogger]; read by the bug-report flow.
final AppLogBuffer appLogBuffer = AppLogBuffer();

/// Application-wide [Logger] instance.
///
/// Security rule (spec §10.1): never log secrets — passwords, private keys
/// and PSKs must be sanitized out before they reach the logger. The
/// [RedactingLogPrinter] is a safety net, not a substitute for that rule.
///
/// The permissive filter keeps events flowing in release builds so the
/// ring buffer has content to attach to bug reports; the console output
/// stays debug-only.
final Logger appLogger = Logger(
  filter: ProductionFilter(),
  // In release the printed output goes nowhere (the console output is
  // debug-only and the ring buffer formats from the event origin), so skip
  // the pretty box work there (audit L5).
  printer: kDebugMode
      ? RedactingLogPrinter(
          PrettyPrinter(
            methodCount: 0,
            // Timestamps make the app log correlatable with server-side
            // logs (installer state file, journald) during e2e debugging.
            dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
          ),
        )
      : RedactingLogPrinter(SimplePrinter()),
  output: MultiOutput([
    if (kDebugMode) ConsoleOutput(),
    appLogBuffer,
  ]),
);

/// Exposes [appLogBuffer] so widgets and tests can read (or override) it.
final Provider<AppLogBuffer> appLogBufferProvider = Provider<AppLogBuffer>(
  (ref) => appLogBuffer,
);

/// Exposes [appLogger] to the widget tree so it can be overridden in tests.
final Provider<Logger> loggerProvider = Provider<Logger>(
  (ref) => appLogger,
);
