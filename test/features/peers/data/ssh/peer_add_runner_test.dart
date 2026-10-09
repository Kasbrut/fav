import 'dart:convert';
import 'dart:typed_data';

import 'package:fav/core/errors/app_exception.dart';
import 'package:fav/core/wireguard/wg_public_key.dart';
import 'package:fav/features/install/domain/ssh_client.dart';
import 'package:fav/features/peers/data/peer_script_source.dart';
import 'package:fav/features/peers/data/ssh/peer_add_runner.dart';
import 'package:fav/features/servers/domain/wireguard_installation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../support/peer_script_bundle.dart';
import '../../../../support/recording_ssh_client.dart';

void main() {
  const successStdout = '''
ADDR=10.13.13.3/32
PUBKEY=AAA=
---BEGIN-CONF---
[Interface]
PrivateKey = BBB
---END-CONF---
''';

  PeerAddRunner buildRunner() {
    final source = PeerScriptSource(
      bundle: FakePeerAssetBundle(),
      expectedHashes: const {},
    );
    return PeerAddRunner(scriptSource: source);
  }

  PeerAddRequest buildRequest({String label = 'phone'}) {
    return PeerAddRequest(
      interfaceName: 'wg0',
      vpnSubnet: '10.13.13.0/24',
      publicEndpoint: 'vpn.example.org',
      wgPort: 51820,
      dns: '1.1.1.1, 1.0.0.1',
      mtu: 1420,
      label: label,
    );
  }

  /// SSH double that answers the staging command with the marker and the
  /// script invocation with [main] (chmod/rm are treated as no-ops).
  RecordingSshClient sshWith(SshCommandResult main) {
    return RecordingSshClient(
      onRun: (cmd) {
        if (cmd.contains('mkdir -m 700')) {
          return const SshCommandResult(
            stdout: 'WG-PEER-STAGED\n',
            stderr: '',
            exitCode: 0,
          );
        }
        if (cmd.startsWith('chmod') || cmd.startsWith('rm')) {
          return const SshCommandResult(stdout: '', stderr: '', exitCode: 0);
        }
        return main;
      },
    );
  }

  test('uploads peer_add.sh, runs under sudo with the requested env', () async {
    final ssh = sshWith(
      const SshCommandResult(stdout: successStdout, stderr: '', exitCode: 0),
    );

    final envelope = await buildRunner().run(
      ssh: ssh,
      password: 'pw',
      request: buildRequest(),
    );

    expect(envelope.address, '10.13.13.3/32');
    expect(envelope.publicKey, 'AAA=');
    expect(envelope.rawConf, contains('PrivateKey = BBB'));

    expect(ssh.uploads, hasLength(1));
    // Staged inside a private per-invocation directory, not a fixed path.
    expect(ssh.uploads.single.remotePath, startsWith('/tmp/wg-peer-'));
    expect(ssh.uploads.single.remotePath, endsWith('/peer_add.sh'));
    // Sudo-wrapped invocation, with the requested env passed via `env VAR=...`.
    final sudoCmd = ssh.runCommands.firstWhere((c) => c.startsWith('sudo'));
    expect(sudoCmd, contains("INTERFACE_NAME='wg0'"));
    expect(sudoCmd, contains("VPN_SUBNET='10.13.13.0/24'"));
    expect(sudoCmd, contains("PUBLIC_ENDPOINT='vpn.example.org'"));
    expect(sudoCmd, contains("WG_PORT='51820'"));
    expect(sudoCmd, contains("DNS='1.1.1.1, 1.0.0.1'"));
    expect(sudoCmd, contains("MTU='1420'"));
    expect(sudoCmd, contains("PEER_LABEL='phone'"));
    expect(sudoCmd, contains(' bash '));
    // Password fed via stdin to sudo -S.
    expect(ssh.runStdins[ssh.runCommands.indexOf(sudoCmd)], 'pw\n');
    // Staging directory removed afterwards (last command).
    expect(ssh.runCommands.last, startsWith('rm -rf'));
  });

  test('v2 uploads manager and sends only manifest identities', () async {
    const privateKey = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=';
    final publicKey = await WgPublicKey.fromPrivateKey(privateKey);
    final stdout =
        '''
FAV_ENVELOPE_VERSION=2
INSTALLATION_ID=installation-1
OPERATION_ID=operation-1
REVISION=2
IPV6_MODE=blocked
ADDR4=10.13.13.2/32
ADDR6=fd12:3456:789a::2/128
PUBKEY=${publicKey.canonical}
---BEGIN-CONF---
[Interface]
PrivateKey = $privateKey
Address = 10.13.13.2/32, fd12:3456:789a::2/128
DNS = 1.1.1.1
MTU = 1420

[Peer]
PublicKey = $privateKey
PresharedKey = $privateKey
Endpoint = vpn.example.org:51820
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
---END-CONF---
''';
    final ssh = sshWith(
      SshCommandResult(stdout: stdout, stderr: '', exitCode: 0),
    );
    final network = NetworkConfiguration(
      schemaVersion: 2,
      installationId: 'installation-1',
      revision: 1,
      ipv6Mode: Ipv6Mode.blocked,
      ipv4Subnet: '10.13.13.0/24',
      ipv6Subnet: 'fd12:3456:789a::/64',
      fallbackIpv6Subnet: 'fd12:3456:789a::/64',
      serverIpv6Address: 'fd12:3456:789a::1/64',
      capabilityStatus: CapabilityStatus.unknown,
      capabilityReason: 'test',
      capabilityCheckedAt: DateTime.utc(2026, 9, 17),
      status: NetworkMetadataStatus.valid,
    );
    await buildRunner().run(
      ssh: ssh,
      password: 'pw',
      request: PeerAddRequest(
        interfaceName: 'wg0',
        vpnSubnet: 'ignored',
        publicEndpoint: 'ignored',
        wgPort: 1,
        dns: 'ignored',
        mtu: 1,
        label: 'phone',
        installationId: 'installation-1',
        operationId: 'operation-1',
        network: network,
      ),
    );
    expect(ssh.uploads, hasLength(2));
    final command = ssh.runCommands.firstWhere(
      (value) => value.startsWith('sudo'),
    );
    expect(command, contains("FAV_CONFIG_VERSION='2'"));
    expect(command, contains("FAV_INSTALLATION_ID='installation-1'"));
    expect(command, contains("FAV_OPERATION_ID='operation-1'"));
    expect(command, isNot(contains('VPN_SUBNET=')));
    expect(command, isNot(contains('PUBLIC_ENDPOINT=')));
    expect(command, isNot(contains('DNS=')));
    expect(command, isNot(contains('MTU=')));
  });

  test(
    'maps exit 41 + ERR-PEER-SUBNET-EXHAUSTED to peerSubnetExhausted',
    () async {
      final ssh = sshWith(
        const SshCommandResult(
          stdout: '',
          stderr: 'ERR-PEER-SUBNET-EXHAUSTED\n',
          exitCode: 41,
        ),
      );

      await expectLater(
        buildRunner().run(
          ssh: ssh,
          password: 'pw',
          request: buildRequest(),
        ),
        throwsA(
          predicate(
            (e) => e is AppException && e.code == ErrorCode.peerSubnetExhausted,
          ),
        ),
      );
    },
  );

  test('uploads override bytes into the private staging dir', () async {
    final override = Uint8List.fromList(utf8.encode('# custom add\n'));
    final ssh = sshWith(
      const SshCommandResult(stdout: successStdout, stderr: '', exitCode: 0),
    );

    await buildRunner().run(
      ssh: ssh,
      password: 'pw',
      request: buildRequest(),
      overrideBytes: override,
    );

    expect(ssh.uploads.single.data, override);
    expect(ssh.uploads.single.remotePath, startsWith('/tmp/wg-peer-'));
    expect(ssh.uploads.single.remotePath, endsWith('/peer_add.sh'));
  });

  test(
    'throws peerApplyFailed when the staging directory cannot be created',
    () async {
      // No marker in stdout → the private dir was not created; the runner must
      // abort before uploading or executing anything (H1).
      final ssh = RecordingSshClient(
        onRun: (cmd) =>
            const SshCommandResult(stdout: '', stderr: '', exitCode: 1),
      );
      await expectLater(
        buildRunner().run(ssh: ssh, password: 'pw', request: buildRequest()),
        throwsA(
          predicate(
            (e) => e is AppException && e.code == ErrorCode.peerApplyFailed,
          ),
        ),
      );
      expect(ssh.uploads, isEmpty);
    },
  );

  test('maps exit 40 + ERR-PEER-APPLY-FAILED to peerApplyFailed', () async {
    final ssh = sshWith(
      const SshCommandResult(
        stdout: '',
        stderr: 'ERR-PEER-APPLY-FAILED\n',
        exitCode: 40,
      ),
    );

    await expectLater(
      buildRunner().run(
        ssh: ssh,
        password: 'pw',
        request: buildRequest(),
      ),
      throwsA(
        predicate(
          (e) => e is AppException && e.code == ErrorCode.peerApplyFailed,
        ),
      ),
    );
  });

  test(
    "maps sudo's password rejection to authInvalidCredentials (F9)",
    () async {
      // A wrong sudo password aborts before the script ever runs: stderr is
      // sudo's own rejection, not an ERR-PEER-* marker. Reporting this as
      // peerApplyFailed ("the peer didn't come up… rolled back") is misleading.
      final ssh = sshWith(
        const SshCommandResult(
          stdout: '',
          stderr:
              'Sorry, try again.\n'
              'sudo: no password was supplied\n'
              'sudo: 1 incorrect password attempt\n',
          exitCode: 1,
        ),
      );

      await expectLater(
        buildRunner().run(ssh: ssh, password: 'pw', request: buildRequest()),
        throwsA(
          predicate(
            (e) =>
                e is AppException && e.code == ErrorCode.authInvalidCredentials,
          ),
        ),
      );
    },
  );

  test('throws peerApplyFailed on an unknown non-zero exit code', () async {
    final ssh = sshWith(
      const SshCommandResult(stdout: '', stderr: '', exitCode: 7),
    );
    await expectLater(
      buildRunner().run(
        ssh: ssh,
        password: 'pw',
        request: buildRequest(),
      ),
      throwsA(
        predicate(
          (e) => e is AppException && e.code == ErrorCode.peerApplyFailed,
        ),
      ),
    );
  });

  test(
    'throws peerParseFailed when stdout is malformed even on exit 0',
    () async {
      final ssh = sshWith(
        const SshCommandResult(
          stdout: 'totally not an envelope',
          stderr: '',
          exitCode: 0,
        ),
      );
      await expectLater(
        buildRunner().run(
          ssh: ssh,
          password: 'pw',
          request: buildRequest(),
        ),
        throwsA(
          predicate(
            (e) => e is AppException && e.code == ErrorCode.peerParseFailed,
          ),
        ),
      );
    },
  );

  test(
    'stages the script in an unpredictable per-invocation path (H1)',
    () async {
      // The remote path must NOT be derivable from the (public) script bytes:
      // a fixed /tmp path lets a local user pre-create the file and race the
      // sudo execution. Two runs with identical bytes must land on different
      // paths, each inside a freshly-created 0700 directory.
      final ssh1 = sshWith(
        const SshCommandResult(stdout: successStdout, stderr: '', exitCode: 0),
      );
      final ssh2 = sshWith(
        const SshCommandResult(stdout: successStdout, stderr: '', exitCode: 0),
      );
      await buildRunner().run(
        ssh: ssh1,
        password: 'pw',
        request: buildRequest(),
      );
      await buildRunner().run(
        ssh: ssh2,
        password: 'pw',
        request: buildRequest(),
      );

      final path1 = ssh1.uploads.single.remotePath;
      final path2 = ssh2.uploads.single.remotePath;
      expect(path1, isNot(path2));
      // A private staging directory is created before the upload.
      expect(
        ssh1.runCommands.any((c) => c.contains('mkdir -m 700')),
        isTrue,
      );
    },
  );

  test('shell-quotes a label containing a single quote correctly', () async {
    final ssh = sshWith(
      const SshCommandResult(stdout: successStdout, stderr: '', exitCode: 0),
    );
    await buildRunner().run(
      ssh: ssh,
      password: 'pw',
      request: buildRequest(label: "Andy's iPad"),
    );
    final sudoCmd = ssh.runCommands.firstWhere((c) => c.startsWith('sudo'));
    // Single quote in the value must be encoded as the '\'' standard form.
    expect(sudoCmd, contains(r"PEER_LABEL='Andy'\''s iPad'"));
  });
}
