import 'package:fav/core/utils/line_diff.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('computeLineDiff', () {
    test('reports every line unchanged for identical input', () {
      final diff = computeLineDiff('a\nb\nc', 'a\nb\nc');
      expect(
        diff.map((line) => line.type),
        everyElement(DiffLineType.unchanged),
      );
      expect(diff.map((line) => line.text), ['a', 'b', 'c']);
    });

    test('marks an inserted line as added', () {
      expect(computeLineDiff('a\nc', 'a\nb\nc'), const [
        DiffLine(DiffLineType.unchanged, 'a'),
        DiffLine(DiffLineType.added, 'b'),
        DiffLine(DiffLineType.unchanged, 'c'),
      ]);
    });

    test('marks a deleted line as removed', () {
      expect(computeLineDiff('a\nb\nc', 'a\nc'), const [
        DiffLine(DiffLineType.unchanged, 'a'),
        DiffLine(DiffLineType.removed, 'b'),
        DiffLine(DiffLineType.unchanged, 'c'),
      ]);
    });

    test('represents a changed line as a removal then an addition', () {
      expect(computeLineDiff('a\nb\nc', 'a\nB\nc'), const [
        DiffLine(DiffLineType.unchanged, 'a'),
        DiffLine(DiffLineType.removed, 'b'),
        DiffLine(DiffLineType.added, 'B'),
        DiffLine(DiffLineType.unchanged, 'c'),
      ]);
    });

    test('handles a full replacement', () {
      expect(computeLineDiff('x', 'y'), const [
        DiffLine(DiffLineType.removed, 'x'),
        DiffLine(DiffLineType.added, 'y'),
      ]);
    });
  });
}
