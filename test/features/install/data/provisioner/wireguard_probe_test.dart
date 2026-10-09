import 'package:fav/features/install/data/provisioner/wireguard_probe.dart';
import 'package:fav/features/install/domain/ssh_client.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../support/recording_ssh_client.dart';

void main() {
  const probe = WireguardProbe();

  test('detects an existing WireGuard installation', () async {
    final client = RecordingSshClient(
      onRun: (command) => const SshCommandResult(
        stdout: 'WG-PRESENT\n',
        stderr: '',
        exitCode: 0,
      ),
    );
    expect(await probe.isWireguardInstalled(client), isTrue);
  });

  test('reports no installation when the conf file is absent', () async {
    final client = RecordingSshClient(
      onRun: (command) => const SshCommandResult(
        stdout: '',
        stderr: '',
        exitCode: 1,
      ),
    );
    expect(await probe.isWireguardInstalled(client), isFalse);
  });
}
