import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Enforces that all shipped locales carry exactly the English key set.
///
/// `gen-l10n` silently falls back on a missing key, so a locale gap is
/// invisible at runtime; this test locks in the 10-locale parity CONTRIBUTING
/// require (previously only en/it were checked, for subsets).
void main() {
  const locales = ['en', 'it', 'de', 'es', 'fr', 'pt', 'ru', 'tr', 'uk', 'zh'];

  Set<String> messageKeys(String locale) {
    final raw = File('lib/l10n/app_$locale.arb').readAsStringSync();
    final json = jsonDecode(raw) as Map<String, dynamic>;
    // Skip @@metadata (@@locale, …) and @-prefixed per-key metadata entries.
    return json.keys.where((k) => !k.startsWith('@')).toSet();
  }

  String message(String locale, String key) {
    final raw = File('lib/l10n/app_$locale.arb').readAsStringSync();
    return (jsonDecode(raw) as Map<String, dynamic>)[key] as String;
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

  test('peer revocation confirmation word is localized and uppercase', () {
    const expected = {
      'en': 'REVOKE',
      'it': 'REVOCA',
      'de': 'WIDERRUFEN',
      'es': 'REVOCAR',
      'fr': 'RÉVOQUER',
      'pt': 'REVOGAR',
      'ru': 'ОТОЗВАТЬ',
      'tr': 'İPTAL ET',
      'uk': 'ВІДКЛИКАТИ',
      'zh': '撤销',
    };

    for (final entry in expected.entries) {
      final word = message(entry.key, 'backupRevokeWord');
      expect(word, entry.value, reason: 'Unexpected ${entry.key} word');
      expect(word, word.toUpperCase(), reason: '${entry.key} is not uppercase');
    }
  });
}
