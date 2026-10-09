import 'package:fav/features/install/application/wireguard_port_reachability_service.dart';
import 'package:fav/features/install/domain/ssh_client.dart';
import 'package:fav/features/servers/domain/wireguard_installation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/recording_ssh_client.dart';

void main() {
  const service = WireguardPortReachabilityService(settleDelay: Duration.zero);

  SshCommandResult ok(String stdout) =>
      SshCommandResult(stdout: stdout, stderr: '', exitCode: 0);

  RecordingSshClient clientWithPackets(int packets) => RecordingSshClient(
    onRun: (command) {
      if (command.contains('FAV_PORT_PROBE_READY')) {
        return ok('FAV_PORT_PROBE_READY');
      }
      if (command.contains('nft list table')) {
        return ok('counter packets $packets bytes 44');
      }
      return ok('');
    },
  );

  test('reports reachable when the marker counter increments', () async {
    final client = clientWithPackets(1);

    final result = await service.check(
      client: client,
      endpoint: '127.0.0.1',
      port: 51820,
    );

    expect(result, WireguardPortReachability.reachable);
    expect(client.runCommands.last, contains('nft delete table'));
  });

  test('reports blocked when the marker never reaches the server', () async {
    final result = await service.check(
      client: clientWithPackets(0),
      endpoint: '127.0.0.1',
      port: 51820,
    );

    expect(result, WireguardPortReachability.blocked);
  });

  test('reports unknown when the remote probe cannot be prepared', () async {
    final client = RecordingSshClient(onRun: (_) => ok(''));

    final result = await service.check(
      client: client,
      endpoint: '127.0.0.1',
      port: 51820,
      useSudo: true,
      sudoPassword: 'secret',
    );

    expect(result, WireguardPortReachability.unknown);
    expect(client.runCommands.join(), isNot(contains('secret')));
    expect(client.runStdins, contains('secret\n'));
  });
}
