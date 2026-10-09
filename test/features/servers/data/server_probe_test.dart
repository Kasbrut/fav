import 'package:fav/core/errors/app_exception.dart';
import 'package:fav/features/servers/data/server_probe.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_ssh_client.dart';

/// Tests for the system probe service.
void main() {
  const probe = ServerProbe();

  Map<String, String> baseResponses() => {
    'cat /etc/os-release':
        'ID=debian\nVERSION_ID="12"\nPRETTY_NAME="Debian 12"',
    'uname -r': '6.1.0-13-amd64',
    'uname -m': 'x86_64',
    'hostname': 'vps',
    'cat /proc/meminfo': 'MemTotal:  2048000 kB',
    'nproc': '2',
    'ls /sys/class/net': 'eth0  wg0  lo',
    'curl -s --max-time 5 https://api.ipify.org': '203.0.113.5',
  };

  test('produces ServerMetadata from the probe command output', () async {
    final metadata = await probe.probe(FakeSshClient(baseResponses()));
    expect(metadata.osId, 'debian');
    expect(metadata.osVersion, '12');
    expect(metadata.kernelVersion, '6.1.0-13-amd64');
    expect(metadata.architecture, 'x86_64');
    expect(metadata.totalMemoryMb, 2000);
    expect(metadata.cpuCount, 2);
    expect(metadata.publicIp, '203.0.113.5');
    expect(metadata.networkInterfaces, ['eth0', 'wg0', 'lo']);
  });

  test('falls back to hostname -I when the echo service fails', () async {
    final responses = baseResponses()
      ..remove('curl -s --max-time 5 https://api.ipify.org')
      ..['hostname -I'] = '10.0.0.5 203.0.113.9';
    final metadata = await probe.probe(FakeSshClient(responses));
    expect(metadata.publicIp, '10.0.0.5');
  });

  test('throws ERR-SYS-01 for an unsupported distribution', () async {
    final responses = baseResponses()
      ..['cat /etc/os-release'] = 'ID=fedora\nVERSION_ID="40"';
    await expectLater(
      probe.probe(FakeSshClient(responses)),
      throwsA(
        isA<AppException>().having(
          (e) => e.code,
          'code',
          ErrorCode.sysUnsupportedDistro,
        ),
      ),
    );
  });

  test('throws ERR-SYS-02 for a kernel too old', () async {
    final responses = baseResponses()..['uname -r'] = '5.4.0-90-generic';
    await expectLater(
      probe.probe(FakeSshClient(responses)),
      throwsA(
        isA<AppException>().having(
          (e) => e.code,
          'code',
          ErrorCode.sysKernelTooOld,
        ),
      ),
    );
  });
}
