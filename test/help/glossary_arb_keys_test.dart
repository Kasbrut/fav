import 'dart:convert';
import 'dart:io';

import 'package:fav/features/help/domain/glossary_entries.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _loadArb(String path) {
  return json.decode(File(path).readAsStringSync()) as Map<String, dynamic>;
}

void main() {
  final en = _loadArb('lib/l10n/app_en.arb');
  final it = _loadArb('lib/l10n/app_it.arb');

  test('every GlossaryEntry has Title + Body in EN and IT', () {
    for (final entry in glossaryEntries) {
      for (final arb in [en, it]) {
        expect(
          arb.containsKey(entry.titleKey),
          isTrue,
          reason: 'missing ${entry.titleKey}',
        );
        expect(
          arb.containsKey(entry.bodyKey),
          isTrue,
          reason: 'missing ${entry.bodyKey}',
        );
      }
    }
  });

  test('no orphan glossary* ARB keys', () {
    final allowed = <String>{
      for (final entry in glossaryEntries) ...[entry.titleKey, entry.bodyKey],
    };
    final pattern = RegExp(r'^glossary[A-Z][A-Za-z0-9]*(Title|Body)$');
    for (final arb in {'EN': en, 'IT': it}.entries) {
      final arbKeys = arb.value.keys
          .where((k) => !k.startsWith('@') && pattern.hasMatch(k))
          .toSet();
      final orphans = arbKeys.difference(allowed);
      expect(
        orphans,
        isEmpty,
        reason: 'orphan glossary* keys in ${arb.key} ARB: $orphans',
      );
    }
  });
}
