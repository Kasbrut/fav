import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every help markdown file has an EN and an IT sibling', () {
    final root = Directory('lib/assets/help');
    final files = root.listSync(recursive: true).whereType<File>().toList();
    final stems = <String, Set<String>>{};
    for (final f in files) {
      final name = f.path.split('/').last;
      final match = RegExp(r'^(.+)\.(en|it)\.md$').firstMatch(name);
      if (match == null) continue;
      final stem = '${f.parent.path}/${match.group(1)!}';
      stems.putIfAbsent(stem, () => {}).add(match.group(2)!);
    }
    for (final entry in stems.entries) {
      expect(
        entry.value,
        containsAll(['en', 'it']),
        reason: 'missing locale for ${entry.key}: ${entry.value}',
      );
    }
  });
}
