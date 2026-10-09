import 'package:fav/features/install/data/run_mappers.dart';
import 'package:fav/features/install/domain/advanced_options.dart';
import 'package:fav/features/install/domain/install_run.dart';
import 'package:fav/features/install/domain/install_step.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('runToMap / runFromMap round-trips a running run', () {
    final run = InstallRun(
      runId: 'run-1',
      serverId: 'srv-1',
      status: RunStatus.running,
      steps: [
        InstallStep(
          key: 'probe',
          status: StepStatus.done,
          label: 'probe',
          startedAt: DateTime(2026, 5, 18, 10),
          completedAt: DateTime(2026, 5, 18, 10, 1),
        ),
        const InstallStep(
          key: 'install_pkgs',
          status: StepStatus.running,
          label: 'install_pkgs',
        ),
      ],
      scriptContentHash: 'abc123',
      scriptWasModified: false,
      startedAt: DateTime(2026, 5, 18, 10),
    );
    expect(runFromMap(runToMap(run)), run);
  });

  test('runToMap / runFromMap round-trips a completed run', () {
    final run = InstallRun(
      runId: 'run-2',
      serverId: 'srv-1',
      status: RunStatus.success,
      steps: const [],
      scriptWasModified: true,
      startedAt: DateTime(2026, 5, 18),
      completedAt: DateTime(2026, 5, 18, 0, 5),
    );
    expect(runFromMap(runToMap(run)), run);
  });

  InstallRun base({RunType runType = RunType.install}) => InstallRun(
    runId: 'r1',
    serverId: 's1',
    status: RunStatus.running,
    steps: const [],
    scriptWasModified: false,
    startedAt: DateTime.utc(2026, 6, 14),
    runType: runType,
  );

  test('round-trips the persisted advanced options (M3)', () {
    // The effective options are persisted on the run so a recovered run can
    // finalize with the interface/port/subnet it was actually launched with,
    // instead of the defaults.
    final run = base().copyWith(
      options: const AdvancedOptions(
        wgPort: 51999,
        vpnSubnet: '10.66.0.0/24',
        interfaceName: 'wg7',
        publicEndpoint: 'vpn.example.org',
        enableMonitoring: false,
        userAuthorizedKeys: ['ssh-ed25519 AAAA test@key'],
      ),
    );
    final restored = runFromMap(runToMap(run));
    expect(restored, run);
    expect(restored.options?.interfaceName, 'wg7');
    expect(restored.options?.userAuthorizedKeys, ['ssh-ed25519 AAAA test@key']);
  });

  test('options stay null for legacy records without them (M3)', () {
    expect(runFromMap(runToMap(base())).options, isNull);
  });

  test('round-trips the management username (M3)', () {
    // The account module 25 deploys the app key to; a recovered run needs it
    // to restore the management identity at finalize (device test
    // 2026-08-19: recovery left the server managed as root+password, so
    // key-only monitoring could never work).
    final run = base().copyWith(managementUsername: 'favops');
    final restored = runFromMap(runToMap(run));
    expect(restored, run);
    expect(restored.managementUsername, 'favops');
    expect(runFromMap(runToMap(base())).managementUsername, isNull);
  });

  test('round-trips the teardown run type', () {
    final restored = runFromMap(runToMap(base(runType: RunType.teardown)));
    expect(restored.runType, RunType.teardown);
  });

  test('round-trips stable v2 request identity and ULA for recovery', () {
    final run = base().copyWith(
      installationId: 'installation-1',
      operationId: 'operation-1',
      ipv6UlaSubnet: 'fd12:3456:789a::/64',
    );
    final recovered = runFromMap(runToMap(run));
    expect(recovered.installationId, run.installationId);
    expect(recovered.operationId, run.operationId);
    expect(recovered.ipv6UlaSubnet, run.ipv6UlaSubnet);
  });

  test('defaults to install when runType is absent (legacy records)', () {
    final map = runToMap(base())..remove('runType');
    expect(runFromMap(map).runType, RunType.install);
  });
}
