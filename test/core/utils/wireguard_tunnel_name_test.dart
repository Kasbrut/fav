import 'package:fav/core/utils/wireguard_tunnel_name.dart';
import 'package:flutter_test/flutter_test.dart';

// WireGuard apps validate the tunnel name (the file name without `.conf`)
// against this pattern; anything else fails to import with "Invalid name".
final RegExp _wireguardNamePattern = RegExp(r'^[a-zA-Z0-9_=+.-]{1,15}$');

void main() {
  group('wireguardConfFileName', () {
    String name(String full) {
      expect(full, endsWith('.conf'));
      return full.substring(0, full.length - '.conf'.length);
    }

    test('keeps short server+peer labels joined with a dash', () {
      final file = wireguardConfFileName(
        serverLabel: 'casa',
        peerLabel: 'iphone',
      );
      expect(file, 'casa-iphone.conf');
    });

    test('uses the server label alone when no peer label is given', () {
      expect(wireguardConfFileName(serverLabel: 'home-vpn'), 'home-vpn.conf');
    });

    test('replaces spaces and strips disallowed characters', () {
      final file = wireguardConfFileName(
        serverLabel: 'My Server!',
        peerLabel: "Luca's phone",
      );
      final base = name(file);
      expect(_wireguardNamePattern.hasMatch(base), isTrue);
      expect(base.contains(' '), isFalse);
    });

    test('never exceeds the 15-character WireGuard limit', () {
      final file = wireguardConfFileName(
        serverLabel: 'production-server-eu-west',
        peerLabel: 'operator-work-laptop',
      );
      final base = name(file);
      expect(base.length, lessThanOrEqualTo(15));
      expect(_wireguardNamePattern.hasMatch(base), isTrue);
    });

    test('balances the budget between a long server and a long peer', () {
      final file = wireguardConfFileName(
        serverLabel: 'aaaaaaaaaaaaaaaa',
        peerLabel: 'bbbbbbbbbbbbbbbb',
      );
      // 7 chars + '-' + 7 chars = 15.
      expect(name(file), 'aaaaaaa-bbbbbbb');
    });

    test('gives the full budget to the peer when the server is short', () {
      final file = wireguardConfFileName(
        serverLabel: 'hq',
        peerLabel: 'verylongpeername',
      );
      final base = name(file);
      expect(base.startsWith('hq-'), isTrue);
      expect(base.length, 15);
    });

    test('falls back to "tunnel" when nothing usable remains', () {
      expect(
        wireguardConfFileName(serverLabel: '   ', peerLabel: '!!!'),
        'tunnel.conf',
      );
      expect(wireguardConfFileName(serverLabel: ''), 'tunnel.conf');
    });

    test('trims edge separators left by sanitizing/truncating', () {
      final file = wireguardConfFileName(serverLabel: '-edge-', peerLabel: '');
      expect(name(file), 'edge');
    });
  });
}
