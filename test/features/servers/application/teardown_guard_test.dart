import 'package:fav/features/servers/application/teardown_guard.dart';
import 'package:fav/features/servers/domain/server.dart';
import 'package:fav/features/servers/domain/wireguard_installation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/server_fakes.dart';

void main() {
  WireguardInstallation hardened({required bool applied}) =>
      WireguardInstallation(
        interfaceName: 'wg0',
        listenPort: 51820,
        vpnSubnet: '10.13.13.0/24',
        serverPublicKey: 'pk',
        peers: const [],
        hardeningApplied: applied,
        installedAt: DateTime(2026, 6, 14),
      );

  Server srv({
    String? sshKeyId = 'srv-1',
    bool hardening = true,
    List<String> ownKeys = const [],
  }) => testServer().copyWith(
    sshKeyId: sshKeyId,
    installation: hardened(applied: hardening),
    userAuthorizedKeys: ownKeys,
  );

  test('flags lockout risk in the dangerous combination', () {
    expect(teardownWouldLockOut(server: srv(), reopenSsh: false), isTrue);
  });

  test('no risk when re-opening SSH', () {
    expect(teardownWouldLockOut(server: srv(), reopenSsh: true), isFalse);
  });

  test('no risk when the operator has own keys', () {
    expect(
      teardownWouldLockOut(
        server: srv(ownKeys: const ['ssh-ed25519 X u']),
        reopenSsh: false,
      ),
      isFalse,
    );
  });

  test('no risk when not hardened', () {
    expect(
      teardownWouldLockOut(server: srv(hardening: false), reopenSsh: false),
      isFalse,
    );
  });

  test('no risk when there is no app key to remove', () {
    expect(
      teardownWouldLockOut(server: srv(sshKeyId: null), reopenSsh: false),
      isFalse,
    );
  });
}
