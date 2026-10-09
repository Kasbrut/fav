import 'package:fav/core/utils/validators.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tests for the input validators (spec §9.2).
void main() {
  test('VPN pools must be canonical /24 networks', () {
    expect(isValidVpnSubnet('10.13.13.0/24'), isTrue);
    for (final invalid in [
      '10.0.0.0/16',
      '10.0.0.64/26',
      '10.0.0.1/24',
      '999.0.0.0/24',
      '010.0.0.0/24',
    ]) {
      expect(isValidVpnSubnet(invalid), isFalse, reason: invalid);
    }
  });
  test('embedded IPv4 must be at the end of IPv6', () {
    expect(isValidIpv6('::ffff:192.0.2.1'), isTrue);
    expect(isValidIpv6('192.0.2.1::'), isFalse);
    expect(isValidIpv6('1:192.0.2.1::'), isFalse);
  });
  test('new passwords reject control characters before upload', () {
    expect(isValidNewPassword('StrongPassword1!\n'), isFalse);
    expect(isValidNewPassword('StrongPassword1!\x7f'), isFalse);
  });

  group('isValidServerLabel', () {
    test('accepts 1-50 characters', () {
      expect(isValidServerLabel('vps'), isTrue);
      expect(isValidServerLabel('a' * 50), isTrue);
    });

    test('rejects empty or overly long values', () {
      expect(isValidServerLabel(''), isFalse);
      expect(isValidServerLabel('a' * 51), isFalse);
    });
  });

  group('isValidPeerLabel', () {
    test('accepts simple labels of various lengths', () {
      expect(isValidPeerLabel('phone'), isTrue);
      expect(isValidPeerLabel('My Laptop'), isTrue);
      expect(isValidPeerLabel('a'), isTrue);
      expect(isValidPeerLabel('a' * 32), isTrue);
    });

    test('accepts Unicode letters and the punctuation subset', () {
      expect(isValidPeerLabel('téléphone'), isTrue);
      expect(isValidPeerLabel('iPad_2024-pro'), isTrue);
      expect(isValidPeerLabel('Server.1'), isTrue);
    });

    test('rejects empty, whitespace-only and overlong values', () {
      expect(isValidPeerLabel(''), isFalse);
      expect(isValidPeerLabel('   '), isFalse);
      expect(isValidPeerLabel('a' * 33), isFalse);
    });

    test('rejects shell metacharacters and control bytes', () {
      expect(isValidPeerLabel(r'phone$(rm -rf /)'), isFalse);
      expect(isValidPeerLabel('phone`whoami`'), isFalse);
      expect(isValidPeerLabel('phone;ls'), isFalse);
      expect(isValidPeerLabel('phone\nname'), isFalse);
      expect(isValidPeerLabel('phone/laptop'), isFalse);
    });
  });

  group('isValidIpv4', () {
    test('accepts valid addresses', () {
      expect(isValidIpv4('10.13.13.0'), isTrue);
      expect(isValidIpv4('255.255.255.255'), isTrue);
    });

    test('rejects invalid addresses', () {
      expect(isValidIpv4('256.0.0.1'), isFalse);
      expect(isValidIpv4('1.2.3'), isFalse);
      expect(isValidIpv4('1.2.3.4.5'), isFalse);
      expect(isValidIpv4('a.b.c.d'), isFalse);
      expect(isValidIpv4('1.2.3.'), isFalse);
    });
  });

  group('isValidIpv6', () {
    test('accepts standard IPv6 forms', () {
      expect(isValidIpv6('::1'), isTrue);
      expect(isValidIpv6('::'), isTrue);
      expect(isValidIpv6('fe80::1'), isTrue);
      expect(isValidIpv6('2001:db8::1'), isTrue);
      expect(
        isValidIpv6('2001:0db8:0000:0000:0000:0000:0000:0001'),
        isTrue,
      );
      expect(isValidIpv6('[2001:db8::1]'), isTrue);
      expect(isValidIpv6('::ffff:192.168.1.1'), isTrue);
    });

    test('rejects malformed IPv6', () {
      expect(isValidIpv6('192.168.1.1'), isFalse);
      expect(isValidIpv6('2001::db8::1'), isFalse);
      expect(isValidIpv6('1:2:3:4:5:6:7:8:9'), isFalse);
      expect(isValidIpv6('gggg::1'), isFalse);
      expect(isValidIpv6('reseed'), isFalse);
    });
  });

  group('isValidHostOrIp', () {
    test('accepts IPv4, IPv6 and hostnames', () {
      expect(isValidHostOrIp('192.168.1.1'), isTrue);
      expect(isValidHostOrIp('vps2.acme.de'), isTrue);
      expect(isValidHostOrIp('localhost'), isTrue);
      expect(isValidHostOrIp('2001:db8::1'), isTrue);
    });

    test('rejects malformed hosts', () {
      expect(isValidHostOrIp(''), isFalse);
      expect(isValidHostOrIp('-bad.example.com'), isFalse);
      expect(isValidHostOrIp('bad_host'), isFalse);
    });
  });

  group('isValidPort', () {
    test('accepts ports 1-65535', () {
      expect(isValidPort('22'), isTrue);
      expect(isValidPort('65535'), isTrue);
    });

    test('rejects out-of-range and non-numeric values', () {
      expect(isValidPort('0'), isFalse);
      expect(isValidPort('65536'), isFalse);
      expect(isValidPort('abc'), isFalse);
      expect(isValidPort(''), isFalse);
    });
  });

  group('username validators', () {
    test('isValidLoginUsername follows the regex', () {
      expect(isValidLoginUsername('root'), isTrue);
      expect(isValidLoginUsername('deploy_1'), isTrue);
      expect(isValidLoginUsername('1bad'), isFalse);
      expect(isValidLoginUsername('Bad'), isFalse);
      expect(isValidLoginUsername(''), isFalse);
    });

    test('isValidNewUsername rejects root', () {
      expect(isValidNewUsername('deploy'), isTrue);
      expect(isValidNewUsername('root'), isFalse);
    });

    test('isValidInterfaceName caps the length at 15 (IFNAMSIZ)', () {
      // Linux limits interface names to 15 chars; a longer one passes the
      // username rule but fails server-side mid-install (audit M8).
      expect(isValidInterfaceName('wg0'), isTrue);
      expect(isValidInterfaceName('a' * 15), isTrue);
      expect(isValidInterfaceName('a' * 16), isFalse);
      expect(isValidInterfaceName('1bad'), isFalse);
      expect(isValidInterfaceName('Bad'), isFalse);
      expect(isValidInterfaceName(''), isFalse);
    });
  });

  group('password validators', () {
    test('isValidLoginPassword requires one character', () {
      expect(isValidLoginPassword('x'), isTrue);
      expect(isValidLoginPassword(''), isFalse);
    });

    test('isValidNewPassword enforces length and character classes', () {
      expect(isValidNewPassword('Abcdef12!xyz'), isTrue);
      expect(isValidNewPassword('Short1!'), isFalse);
      expect(isValidNewPassword('alllowercaseonly'), isFalse);
      expect(isValidNewPassword('abcdefghijkl12'), isFalse);
    });

    test('passwordsMatch compares the two values', () {
      expect(passwordsMatch('a', 'a'), isTrue);
      expect(passwordsMatch('a', 'b'), isFalse);
    });
  });

  group('isValidCidrV4', () {
    test('accepts valid CIDR blocks', () {
      expect(isValidCidrV4('10.13.13.0/24'), isTrue);
      expect(isValidCidrV4('0.0.0.0/0'), isTrue);
    });

    test('rejects invalid CIDR blocks', () {
      expect(isValidCidrV4('10.13.13.0'), isFalse);
      expect(isValidCidrV4('10.13.13.0/33'), isFalse);
      expect(isValidCidrV4('999.0.0.0/24'), isFalse);
    });
  });

  group('IPv6 network validators', () {
    test('accept canonical /64 ULA and GUA networks', () {
      expect(isValidCidrV6('2001:db8::/64'), isTrue);
      expect(isValidVpnSubnetV6('fd12:3456:789a::/64'), isTrue);
      expect(isValidVpnSubnetV6('2001:4860:4860::/64'), isTrue);
    });
    test('rejects noncanonical, host bits and disallowed prefixes', () {
      for (final value in [
        'fd12:3456:789a::1/64',
        'FD12:3456:789A::/64',
        'fe80::/64',
        '2001:db8::/64',
        '[fd12:3456:789a::]/64',
      ]) {
        expect(isValidVpnSubnetV6(value), isFalse, reason: value);
      }
      for (final suffix in ['+64', '0x40', '64\n']) {
        expect(isValidCidrV6('fd12:3456:789a::/$suffix'), isFalse);
      }
    });
  });

  group('isValidMtu', () {
    test('accepts 576-1500', () {
      expect(isValidMtu('576'), isTrue);
      expect(isValidMtu('1420'), isTrue);
      expect(isValidMtu('1500'), isTrue);
    });

    test('rejects out-of-range values', () {
      expect(isValidMtu('575'), isFalse);
      expect(isValidMtu('1501'), isFalse);
      expect(isValidMtu('x'), isFalse);
    });
  });

  test('full tunnel MTU is 1280 through 1500', () {
    expect(isValidFullTunnelMtu('1280'), isTrue);
    expect(isValidFullTunnelMtu('1500'), isTrue);
    expect(isValidFullTunnelMtu('1279'), isFalse);
    expect(isValidFullTunnelMtu('1501'), isFalse);
    expect(isValidFullTunnelMtu('invalid'), isFalse);
  });

  group('isValidDnsList', () {
    test('accepts comma-separated IPv4 lists', () {
      expect(isValidDnsList('1.1.1.1'), isTrue);
      expect(isValidDnsList('1.1.1.1, 1.0.0.1'), isTrue);
    });

    test('rejects empty entries and invalid IPs', () {
      expect(isValidDnsList(''), isFalse);
      expect(isValidDnsList('1.1.1.1,'), isFalse);
      expect(isValidDnsList('1.1.1.1, not-an-ip'), isFalse);
      expect(isValidDnsList('2001:4860:4860::8888, 1.1.1.1'), isTrue);
      expect(isValidDnsList('[::1]'), isFalse);
      expect(isValidDnsList('[::1]:53'), isFalse);
      expect(isValidDnsList('1.1.1.1:53'), isFalse);
      expect(isValidDnsList('fe80::1%eth0'), isFalse);
    });
  });
}
