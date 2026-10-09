import 'package:fav/core/utils/ipv6.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('canonical formatting uses the longest first zero run', () {
    expect(canonicalizeIpv6('2001:0db8:0:0:1:0:0:1'), '2001:db8::1:0:0:1');
    expect(canonicalizeIpv6('0:0:1:0:0:2:3:4'), '::1:0:0:2:3:4');
    expect(canonicalizeIpv6('0:0:0:0:0:0:0:0'), '::');
    expect(canonicalizeIpv6('1:0:0:0:0:0:0:0'), '1::');
    expect(canonicalizeIpv6('0:0:0:1:0:0:0:0'), '0:0:0:1::');
  });

  test('embedded IPv4 and malformed tails are handled', () {
    expect(canonicalizeIpv6('::ffff:192.0.2.1'), '::ffff:c000:201');
    expect(parseIpv6('192.0.2.1::'), isNull);
    expect(parseIpv6('::ffff:192.00.2.1'), isNull);
    expect(parseIpv6('::1\n'), isNull);
  });

  test('prefix membership handles bit boundaries', () {
    const address = '2001:db8:1234:5678::a';
    expect(ipv6InPrefix(address, '::', 0), isTrue);
    expect(ipv6InPrefix(address, '2001::', 1), isTrue);
    expect(ipv6InPrefix(address, '2001:db8:1234:5678::', 63), isTrue);
    expect(ipv6InPrefix(address, '2001:db8:1234:5678::', 64), isTrue);
    expect(ipv6InPrefix(address, '2001:db8:1234:5678::', 127), isFalse);
    expect(ipv6InPrefix(address, address, 128), isTrue);
  });

  test('slots are numeric IPv6 addresses, with server at one', () {
    const prefix = 'fd12:3456:789a::/64';
    expect(ipv6AddressForSlot(prefix, 1), 'fd12:3456:789a::1');
    expect(ipv6AddressForSlot(prefix, 10), 'fd12:3456:789a::a');
    expect(ipv6AddressForSlot(prefix, 254), 'fd12:3456:789a::fe');
    expect(ipv6AddressForSlot('fd12:3456:789a::1/64', 2), isNull);
    expect(ipv6AddressForSlot(prefix, 255), isNull);
  });

  test('ULA generation accepts deterministic five-byte global IDs', () {
    expect(
      generateUlaSubnet(randomBytes: [0, 1, 2, 3, 4]),
      'fd00:102:304::/64',
    );
    expect(
      generateUlaSubnet(randomBytes: [255, 255, 255, 255, 255]),
      'fdff:ffff:ffff::/64',
    );
    expect(
      () => generateUlaSubnet(randomBytes: [256, 0, 0, 0, 0]),
      throwsArgumentError,
    );
  });

  test('parser and formatter enforce byte and literal boundaries', () {
    expect(canonicalizeIpv6('1:2:3:0:5:6:7:8'), '1:2:3:0:5:6:7:8');
    expect(canonicalizeIpv6('ABCD:1:2:3:4:5:6:7'), 'abcd:1:2:3:4:5:6:7');
    expect(parseIpv6('1:2:3:4:5:6:192.0.2.1'), [
      0,
      1,
      0,
      2,
      0,
      3,
      0,
      4,
      0,
      5,
      0,
      6,
      192,
      0,
      2,
      1,
    ]);
    for (final value in [
      '',
      ':',
      ':::',
      '1::2::3',
      '[::1]',
      'fe80::1%en0',
      '1:2:3:4:5:6:7',
      '1:2:3:4:5:6:7:8:9',
      '::ffff:256.0.0.1',
      '::ffff:1.2.3.4:5',
      '1:2:3:4:5:6::192.0.2.1',
    ]) {
      expect(parseIpv6(value), isNull, reason: value);
    }
    expect(() => formatIpv6([0]), throwsArgumentError);
    expect(
      () => formatIpv6([...List<int>.filled(15, 0), -1]),
      throwsArgumentError,
    );
    expect(
      () => formatIpv6([...List<int>.filled(15, 0), 256]),
      throwsArgumentError,
    );
  });

  test('membership rejects adjacent prefixes and invalid CIDR lengths', () {
    expect(ipv6InPrefix('8000::', '::', 1), isFalse);
    expect(ipv6InPrefix('2001:db8:0:1::', '2001:db8::', 63), isTrue);
    expect(ipv6InPrefix('2001:db8:0:2::', '2001:db8::', 63), isFalse);
    expect(ipv6InPrefix('::b', '::a', 127), isTrue);
    expect(ipv6InPrefix('::c', '::a', 127), isFalse);
    expect(ipv6InPrefix('::b', '::a', 128), isFalse);
    expect(ipv6InPrefix('::', '::', -1), isFalse);
    expect(ipv6InPrefix('::', '::', 129), isFalse);
    expect(isIpv6InPrefix('fd12::2', 'fd12::/64'), isTrue);
    for (final suffix in ['', '+64', '0x40', '64\n', '129', '-1']) {
      expect(isIpv6InPrefix('fd12::2', 'fd12::/$suffix'), isFalse);
    }
  });

  test('allocator and ULA input limits are enforced', () {
    for (final slot in [-1, 0, 255]) {
      expect(ipv6AddressForSlot('fd12::/64', slot), isNull);
    }
    expect(ipv6AddressForSlot('fd12::/63', 2), isNull);
    expect(ipv6AddressForSlot('fd12::', 2), 'fd12::2');
    expect(generateUlaSubnet(randomBytes: [0, 0, 0, 0, 0]), 'fd00::/64');
    for (final bytes in [
      <int>[],
      [0, 1, 2, 3],
      [-1, 0, 0, 0, 0],
    ]) {
      expect(() => generateUlaSubnet(randomBytes: bytes), throwsArgumentError);
    }
  });
}
