import 'package:dart_zxcvbn/dart_zxcvbn.dart';

/// Qualitative password strength levels shown to the user (spec §9.3).
enum PasswordStrength {
  /// Weak password (zxcvbn score 0–1); the form must block submission.
  weak,

  /// Acceptable password (zxcvbn score 2); allowed with a warning.
  fair,

  /// Strong password (zxcvbn score 3–4).
  strong,
}

/// Evaluates [password] with the zxcvbn algorithm and maps the resulting
/// score (0–4) to a [PasswordStrength] level (spec §9.3).
///
/// An empty password is reported as [PasswordStrength.weak].
PasswordStrength evaluatePasswordStrength(String password) {
  if (password.isEmpty) {
    return PasswordStrength.weak;
  }
  final score = zxcvbn(password).score;
  if (score <= 1) {
    return PasswordStrength.weak;
  }
  if (score <= 2) {
    return PasswordStrength.fair;
  }
  return PasswordStrength.strong;
}
