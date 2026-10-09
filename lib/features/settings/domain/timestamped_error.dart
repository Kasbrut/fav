import 'package:meta/meta.dart';

/// A single entry in the persisted error history buffer (cap 20 in the
/// repository). Stores only the stable `ErrorCode.id` plus a UTC timestamp;
/// no detail strings, no PII.
@immutable
class TimestampedError {
  /// Creates a new entry.
  const TimestampedError({required this.timestamp, required this.codeId});

  /// UTC timestamp.
  final DateTime timestamp;

  /// `ErrorCode.id` string (e.g. `ERR-CONN-01`).
  final String codeId;

  /// JSON-shaped map for persistence.
  Map<String, dynamic> toJson() => {
    'ts': timestamp.toUtc().toIso8601String(),
    'code': codeId,
  };

  /// Parses [json] safely. Returns `null` if either field is missing or
  /// malformed.
  static TimestampedError? fromJson(Map<dynamic, dynamic> json) {
    final ts = json['ts'];
    final code = json['code'];
    if (ts is! String || code is! String) return null;
    final parsed = DateTime.tryParse(ts);
    if (parsed == null) return null;
    return TimestampedError(timestamp: parsed.toUtc(), codeId: code);
  }

  @override
  bool operator ==(Object other) =>
      other is TimestampedError &&
      other.timestamp == timestamp &&
      other.codeId == codeId;

  @override
  int get hashCode => Object.hash(timestamp, codeId);
}
