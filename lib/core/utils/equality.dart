// Pure-Dart equality helpers for collection fields. The domain layer must not
// import Flutter, so `listEquals` from `package:flutter/foundation.dart` is
// unavailable here.

/// Returns `true` when [a] and [b] hold equal elements in the same order.
bool listEquals<T>(List<T>? a, List<T>? b) {
  if (identical(a, b)) {
    return true;
  }
  if (a == null || b == null || a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}
