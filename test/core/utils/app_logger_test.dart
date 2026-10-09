import 'package:fav/core/utils/app_logger.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';

class _FixedPrinter extends LogPrinter {
  _FixedPrinter(this.lines);

  final List<String> lines;

  @override
  List<String> log(LogEvent event) => lines;
}

/// Tests for log secret redaction.
void main() {
  test('redacts secret-keyed assignments', () {
    expect(redactSecrets('password: hunter2'), 'password: <redacted>');
    expect(redactSecrets('PSK=abc123'), 'PSK=<redacted>');
    expect(redactSecrets('private_key: xyz'), 'private_key: <redacted>');
  });

  test('redacts every keyword the regex covers', () {
    expect(redactSecrets('passwd=root123'), 'passwd=<redacted>');
    expect(redactSecrets('secret = s3cr3t'), 'secret = <redacted>');
    expect(redactSecrets('token: ghp_abc'), 'token: <redacted>');
    expect(redactSecrets('preshared_key: kkk'), 'preshared_key: <redacted>');
    // The keyword and its separator may use a space instead of an underscore.
    expect(redactSecrets('preshared key = kkk'), 'preshared key = <redacted>');
    expect(redactSecrets('private key: zzz'), 'private key: <redacted>');
  });

  test('redaction is case-insensitive', () {
    expect(redactSecrets('PASSWORD: Hunter2'), 'PASSWORD: <redacted>');
    expect(redactSecrets('Token=abc'), 'Token=<redacted>');
  });

  test(
    'does not over-redact: a keyword without an assignment is untouched',
    () {
      // No `:`/`=` after the keyword, so nothing should be replaced.
      expect(
        redactSecrets('the password was rejected by the server'),
        'the password was rejected by the server',
      );
      expect(redactSecrets('rotating the token now'), 'rotating the token now');
      expect(
        redactSecrets('connecting to host:port 10.0.0.5:22'),
        'connecting to host:port 10.0.0.5:22',
      );
    },
  );

  test('redacts lines containing private key material', () {
    expect(
      redactSecrets('-----BEGIN OPENSSH PRIVATE KEY-----'), // gitleaks:allow
      '<redacted: private key material>',
    );
  });

  test('leaves ordinary lines untouched', () {
    expect(
      redactSecrets('connecting to host 10.0.0.5'),
      'connecting to host 10.0.0.5',
    );
  });

  test('RedactingLogPrinter redacts the wrapped printer output', () {
    final printer = RedactingLogPrinter(
      _FixedPrinter(['password: topsecret', 'plain line']),
    );
    final output = printer.log(LogEvent(Level.info, 'message'));
    expect(output, ['password: <redacted>', 'plain line']);
  });

  group('AppLogBuffer', () {
    OutputEvent event(String message, {Level level = Level.info}) {
      final origin = LogEvent(level, message, time: DateTime(2026, 8, 19, 12));
      return OutputEvent(origin, const []);
    }

    test('keeps plain, timestamped, level-tagged lines', () {
      final buffer = AppLogBuffer(capacity: 10)
        ..output(event('connecting to server'));
      expect(buffer.lines, hasLength(1));
      expect(buffer.lines.single, contains('INFO'));
      expect(buffer.lines.single, contains('connecting to server'));
      expect(buffer.lines.single, contains('2026-08-19'));
    });

    test('caps at the configured capacity, dropping the oldest', () {
      final buffer = AppLogBuffer(capacity: 3);
      for (var i = 0; i < 5; i++) {
        buffer.output(event('line $i'));
      }
      expect(buffer.lines, hasLength(3));
      expect(buffer.lines.first, contains('line 2'));
      expect(buffer.lines.last, contains('line 4'));
    });

    test('redacts secrets before buffering (never stored raw)', () {
      final buffer = AppLogBuffer(capacity: 10)
        ..output(event('sudo password=hunter2 rejected'));
      expect(buffer.lines.single, isNot(contains('hunter2')));
      expect(buffer.lines.single, contains('<redacted>'));
    });

    test('splits multi-line messages so the cap counts real lines', () {
      final buffer = AppLogBuffer(capacity: 3)..output(event('a\nb\nc\nd'));
      expect(buffer.lines, hasLength(3));
      expect(buffer.lines.last, contains('d'));
    });

    test('suppresses the body of a PEM block, not just its header (M3)', () {
      // redactSecrets is per-line: the BEGIN line was redacted but the
      // base64 body between BEGIN/END survived. No first-party call site
      // logs a PEM, but user-edited installer scripts can.
      final buffer = AppLogBuffer(capacity: 10)
        ..output(
          event(
            '-----BEGIN OPENSSH PRIVATE KEY-----\n' // gitleaks:allow
            'AAAAB3NzaC1yc2EAAAADAQABAAABgQ\n'
            '-----END OPENSSH PRIVATE KEY-----\n'
            'after the block',
          ),
        );
      final joined = buffer.lines.join('\n');
      expect(joined, isNot(contains('AAAAB3NzaC1yc2E')));
      expect(joined, contains('after the block'));
    });

    test('clear drops every buffered line (M4)', () {
      final buffer = AppLogBuffer(capacity: 10)..output(event('sensitive'));
      expect(buffer.lines, isNotEmpty);
      buffer.clear();
      expect(buffer.lines, isEmpty);
    });
  });

  group('redactSecretLines', () {
    test('replaces a whole PEM block with the redaction marker', () {
      final redacted = redactSecretLines([
        'before',
        '-----BEGIN PRIVATE KEY-----', // gitleaks:allow
        'AAAAB3NzaC1yc2EAAAADAQABAAABgQ',
        '-----END PRIVATE KEY-----',
        'after',
      ]);
      expect(redacted.join('\n'), isNot(contains('AAAAB3NzaC1yc2E')));
      expect(redacted.first, 'before');
      expect(redacted.last, 'after');
    });

    test('still applies the per-line redaction outside blocks', () {
      expect(
        redactSecretLines(['password: hunter2']).single,
        'password: <redacted>',
      );
    });
  });
}
