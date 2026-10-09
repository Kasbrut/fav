import 'package:meta/meta.dart';

/// The role of a line within a [computeLineDiff] result.
enum DiffLineType {
  /// Present unchanged in both versions.
  unchanged,

  /// Present only in the modified version.
  added,

  /// Present only in the original version.
  removed,
}

/// One line of a line-by-line diff.
@immutable
class DiffLine {
  /// Creates a [DiffLine] of [type] holding [text].
  const DiffLine(this.type, this.text);

  /// Whether the line was added, removed, or left unchanged.
  final DiffLineType type;

  /// The line content, without a trailing newline.
  final String text;

  @override
  bool operator ==(Object other) =>
      other is DiffLine && other.type == type && other.text == text;

  @override
  int get hashCode => Object.hash(type, text);
}

/// Computes a line-by-line diff describing how to turn [original] into
/// [modified], based on the longest common subsequence of their lines
/// (spec §8.5 — diff of a customized installer script vs the default).
List<DiffLine> computeLineDiff(String original, String modified) {
  final a = original.split('\n');
  final b = modified.split('\n');
  final n = a.length;
  final m = b.length;

  // lcs[i][j] = length of the longest common subsequence of a[i..] and b[j..].
  final lcs = List.generate(
    n + 1,
    (_) => List<int>.filled(m + 1, 0),
    growable: false,
  );
  for (var i = n - 1; i >= 0; i--) {
    for (var j = m - 1; j >= 0; j--) {
      lcs[i][j] = a[i] == b[j]
          ? lcs[i + 1][j + 1] + 1
          : (lcs[i + 1][j] >= lcs[i][j + 1] ? lcs[i + 1][j] : lcs[i][j + 1]);
    }
  }

  // Walk the table to emit unchanged, removed and added lines in order.
  final result = <DiffLine>[];
  var i = 0;
  var j = 0;
  while (i < n && j < m) {
    if (a[i] == b[j]) {
      result.add(DiffLine(DiffLineType.unchanged, a[i]));
      i++;
      j++;
    } else if (lcs[i + 1][j] >= lcs[i][j + 1]) {
      result.add(DiffLine(DiffLineType.removed, a[i]));
      i++;
    } else {
      result.add(DiffLine(DiffLineType.added, b[j]));
      j++;
    }
  }
  for (; i < n; i++) {
    result.add(DiffLine(DiffLineType.removed, a[i]));
  }
  for (; j < m; j++) {
    result.add(DiffLine(DiffLineType.added, b[j]));
  }
  return result;
}
