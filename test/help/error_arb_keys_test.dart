import 'dart:convert';
import 'dart:io';

import 'package:fav/core/errors/app_exception.dart';
import 'package:flutter_test/flutter_test.dart';

String _camelKeyForCode(ErrorCode code) {
  // ErrorCode.connHostUnreachable.name == 'connHostUnreachable'.
  // ARB stem is 'err' + capitalized name → 'errConnHostUnreachable'.
  final n = code.name;
  return 'err${n[0].toUpperCase()}${n.substring(1)}';
}

Map<String, dynamic> _loadArb(String path) {
  return json.decode(File(path).readAsStringSync()) as Map<String, dynamic>;
}

void main() {
  final en = _loadArb('lib/l10n/app_en.arb');
  final it = _loadArb('lib/l10n/app_it.arb');

  test('every ErrorCode has Message + Cause + Fix in EN', () {
    for (final code in ErrorCode.values) {
      final stem = _camelKeyForCode(code);
      expect(en.containsKey(stem), isTrue, reason: 'EN missing $stem');
      expect(
        en.containsKey('${stem}Cause'),
        isTrue,
        reason: 'EN missing ${stem}Cause',
      );
      expect(
        en.containsKey('${stem}Fix'),
        isTrue,
        reason: 'EN missing ${stem}Fix',
      );
    }
  });

  test('every ErrorCode has Message + Cause + Fix in IT', () {
    for (final code in ErrorCode.values) {
      final stem = _camelKeyForCode(code);
      expect(it.containsKey(stem), isTrue, reason: 'IT missing $stem');
      expect(
        it.containsKey('${stem}Cause'),
        isTrue,
        reason: 'IT missing ${stem}Cause',
      );
      expect(
        it.containsKey('${stem}Fix'),
        isTrue,
        reason: 'IT missing ${stem}Fix',
      );
    }
  });

  test('no orphan err* keys without an enum match', () {
    final allowed = <String>{
      for (final code in ErrorCode.values) ...[
        _camelKeyForCode(code),
        '${_camelKeyForCode(code)}Cause',
        '${_camelKeyForCode(code)}Fix',
      ],
    };
    final pattern = RegExp(r'^err[A-Z][A-Za-z0-9]*$');
    for (final entry in {'EN': en, 'IT': it}.entries) {
      final arbKeys = entry.value.keys
          .where((k) => !k.startsWith('@') && pattern.hasMatch(k))
          .toSet();
      final orphans = arbKeys.difference(allowed);
      expect(
        orphans,
        isEmpty,
        reason: 'Orphan err* keys in ${entry.key} ARB: $orphans',
      );
    }
  });
}
