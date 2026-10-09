import 'package:fav/core/utils/password_strength.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tests for the zxcvbn-based password strength evaluation (spec §9.3).
void main() {
  test('empty password is weak', () {
    expect(evaluatePasswordStrength(''), PasswordStrength.weak);
  });

  test('very short password is weak', () {
    expect(evaluatePasswordStrength('a'), PasswordStrength.weak);
  });

  test('long complex password is strong', () {
    expect(
      evaluatePasswordStrength(r'9xK#pL2$mQ7!vR4&zT8wB1n'),
      PasswordStrength.strong,
    );
  });

  test('every sample maps to a defined strength level', () {
    const samples = ['abc', 'Sunshine99', 'Wq7!pZ', 'hunter2hunter2'];
    for (final password in samples) {
      final level = evaluatePasswordStrength(password);
      expect(PasswordStrength.values, contains(level));
    }
  });
}
