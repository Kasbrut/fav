import 'package:meta/meta.dart';

/// The category of an "obviously dangerous" bash pattern recognised in an
/// imported `.sh` script (spec §8.6).
///
/// The list intentionally covers only the most common remote-exec idioms;
/// it is not a sandbox or a static analyser, just a warning surface so the
/// user knows when an imported script reaches out and runs code from the
/// network without verification.
enum SuspiciousPatternKind {
  /// `curl … | bash` — fetches content and pipes it straight into a shell.
  remoteExecPipe,

  /// `eval "$(curl …)"` or `eval $(wget …)` — evaluates remote content.
  remoteExecEval,

  /// `bash <(curl …)` — process substitution feeding a shell.
  remoteExecProcSub,
}

/// One occurrence of a [SuspiciousPatternKind] in a script.
@immutable
class SuspiciousPattern {
  /// Creates a [SuspiciousPattern].
  const SuspiciousPattern({
    required this.line,
    required this.text,
    required this.kind,
  });

  /// 1-based line number of the match.
  final int line;

  /// Full line content (trailing whitespace trimmed).
  final String text;

  /// What kind of pattern matched.
  final SuspiciousPatternKind kind;

  @override
  bool operator ==(Object other) {
    return other is SuspiciousPattern &&
        other.line == line &&
        other.text == text &&
        other.kind == kind;
  }

  @override
  int get hashCode => Object.hash(line, text, kind);
}

// `curl|wget|fetch` followed by `| bash` / `| sh` / `| /bin/(ba)?sh` / `| zsh`
// somewhere later on the same line. Tolerant of arguments between the fetcher
// and the pipe.
final RegExp _pipeToShell = RegExp(
  r'\b(?:curl|wget|fetch)\b[^|\n#]*\|\s*'
  r'(?:bash|sh|zsh|/bin/(?:ba|z)?sh)\b',
);

// `eval` followed by `$(curl …)` / `$(wget …)` / `` `curl …` `` / a bare
// fetcher (e.g. `eval $(curl -fsSL …)`).
final RegExp _evalRemote = RegExp(
  r'\beval\b[^#\n]*'
  r'(?:\$\(\s*(?:curl|wget|fetch)\b|`\s*(?:curl|wget|fetch)\b)',
);

// `bash <(curl …)` / `sh <(wget …)` — process substitution feeding a shell.
final RegExp _procSubShell = RegExp(
  r'\b(?:bash|sh|zsh|/bin/(?:ba|z)?sh)\b\s*<\(\s*(?:curl|wget|fetch)\b',
);

bool _isCommentOnly(String line) {
  final trimmed = line.trimLeft();
  return trimmed.startsWith('#');
}

/// Scans [content] for "obviously dangerous" remote-execution idioms.
///
/// Returns one [SuspiciousPattern] per matching line, ordered by line number.
/// The function NEVER blocks: the caller is expected to show the matches to
/// the user as a warning with an explicit "Import anyway" choice (spec §8.6).
/// Comment-only lines are skipped.
List<SuspiciousPattern> detectSuspiciousScriptPatterns(String content) {
  final results = <SuspiciousPattern>[];
  final lines = content.split('\n');
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i].replaceAll(RegExp(r'\s+$'), '');
    if (_isCommentOnly(line)) {
      continue;
    }
    final SuspiciousPatternKind? kind;
    if (_pipeToShell.hasMatch(line)) {
      kind = SuspiciousPatternKind.remoteExecPipe;
    } else if (_evalRemote.hasMatch(line)) {
      kind = SuspiciousPatternKind.remoteExecEval;
    } else if (_procSubShell.hasMatch(line)) {
      kind = SuspiciousPatternKind.remoteExecProcSub;
    } else {
      kind = null;
    }
    if (kind != null) {
      results.add(
        SuspiciousPattern(line: i + 1, text: line, kind: kind),
      );
    }
  }
  return results;
}
