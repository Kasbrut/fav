import 'package:fav/features/servers/data/probe_parsers.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tests for the system probe parsers.
void main() {
  group('parseOsRelease', () {
    test('parses key=value lines and strips quotes', () {
      const content =
          'ID=debian\n'
          'VERSION_ID="12"\n'
          'PRETTY_NAME="Debian GNU/Linux 12 (bookworm)"\n'
          '# a comment\n'
          '\n'
          "NAME='Debian'";
      final result = parseOsRelease(content);
      expect(result['ID'], 'debian');
      expect(result['VERSION_ID'], '12');
      expect(result['PRETTY_NAME'], 'Debian GNU/Linux 12 (bookworm)');
      expect(result['NAME'], 'Debian');
    });
  });

  group('isDistroSupported', () {
    test('accepts debian and ubuntu, rejects others', () {
      expect(isDistroSupported('debian'), isTrue);
      expect(isDistroSupported('ubuntu'), isTrue);
      expect(isDistroSupported('fedora'), isFalse);
      expect(isDistroSupported(''), isFalse);
    });
  });

  group('isKernelSupported', () {
    test('accepts kernel 5.6 and newer', () {
      expect(isKernelSupported('6.1.0-13-amd64'), isTrue);
      expect(isKernelSupported('5.6.0'), isTrue);
      expect(isKernelSupported('5.10.0-21-amd64'), isTrue);
    });

    test('rejects kernels older than 5.6 and unparseable input', () {
      expect(isKernelSupported('5.4.0-90-generic'), isFalse);
      expect(isKernelSupported('4.19.0'), isFalse);
      expect(isKernelSupported('not-a-kernel'), isFalse);
    });
  });

  group('parseMemTotalMb', () {
    test('converts the MemTotal kB value to MB', () {
      const meminfo = 'MemTotal:       2048000 kB\nMemFree:    10240 kB';
      expect(parseMemTotalMb(meminfo), 2000);
    });

    test('returns 0 when MemTotal is absent', () {
      expect(parseMemTotalMb('MemFree: 100 kB'), 0);
    });
  });
}
