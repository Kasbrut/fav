import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Enforces that all shipped locales carry exactly the English key set.
///
/// `gen-l10n` silently falls back on a missing key, so a locale gap is
/// invisible at runtime; this test locks in the 10-locale parity CONTRIBUTING
/// require (previously only en/it were checked, for subsets).
void main() {
  const locales = [
    'en',
    'it',
    'de',
    'es',
    'fr',
    'pt',
    'ru',
    'tr',
    'uk',
    'zh',
  ];

  Set<String> messageKeys(String locale) {
    final raw = File('lib/l10n/app_$locale.arb').readAsStringSync();
    final json = jsonDecode(raw) as Map<String, dynamic>;
    // Skip @@metadata (@@locale, …) and @-prefixed per-key metadata entries.
    return json.keys.where((k) => !k.startsWith('@')).toSet();
  }

  test('every shipped locale has exactly the English message key set', () {
    final en = messageKeys('en');
    expect(en, isNotEmpty);
    for (final locale in locales.where((l) => l != 'en')) {
      final keys = messageKeys(locale);
      expect(
        keys.difference(en),
        isEmpty,
        reason: 'app_$locale.arb has keys not in app_en.arb',
      );
      expect(
        en.difference(keys),
        isEmpty,
        reason: 'app_$locale.arb is missing keys present in app_en.arb',
      );
    }
  });
}
