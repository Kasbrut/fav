import 'package:crypto/crypto.dart';

/// Returns the lowercase hexadecimal SHA-256 digest of [data].
///
/// Used to fingerprint the installer scripts (spec §8.5, §8.6). Pure Dart, so
/// it is testable without a Flutter binding.
String sha256Hex(List<int> data) => sha256.convert(data).toString();
