import 'package:fav/features/install/domain/advanced_options.dart';
import 'package:fav/features/install/domain/install_run.dart';
import 'package:fav/features/install/domain/install_step.dart';
import 'package:fav/features/install/domain/new_user_spec.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tests for the install-feature domain entities.
void main() {
  InstallStep buildStep() => InstallStep(
    key: 'probe',
    status: StepStatus.running,
    label: 'Probe',
    startedAt: DateTime(2026, 5, 18),
  );

  InstallRun buildRun() => InstallRun(
    runId: 'run-1',
    serverId: 'srv-1',
    status: RunStatus.running,
    steps: [buildStep()],
    scriptWasModified: false,
    startedAt: DateTime(2026, 5, 18),
  );

  group('InstallStep', () {
    test('equality, hashCode and copyWith', () {
      expect(buildStep(), equals(buildStep()));
      expect(buildStep().hashCode, equals(buildStep().hashCode));
      final done = buildStep().copyWith(status: StepStatus.done);
      expect(done.status, StepStatus.done);
      expect(buildStep(), isNot(equals(done)));
    });
  });

  group('InstallRun', () {
    test('equality with the steps list', () {
      expect(buildRun(), equals(buildRun()));
      expect(buildRun().hashCode, equals(buildRun().hashCode));
      final noSteps = buildRun().copyWith(steps: const []);
      expect(buildRun(), isNot(equals(noSteps)));
    });

    test('copyWith updates the status', () {
      expect(
        buildRun().copyWith(status: RunStatus.success).status,
        RunStatus.success,
      );
    });
  });

  group('AdvancedOptions', () {
    test('default values match the spec', () {
      const options = AdvancedOptions();
      expect(options.wgPort, 51820);
      expect(options.vpnSubnet, '10.13.13.0/24');
      expect(options.dns, '1.1.1.1, 1.0.0.1');
      expect(options.mtu, 1420);
      expect(options.interfaceName, 'wg0');
      expect(options.enableHardening, isFalse);
      expect(options.backupExistingConfig, isTrue);
    });

    test('equality, hashCode and copyWith', () {
      expect(const AdvancedOptions(), equals(const AdvancedOptions()));
      expect(
        const AdvancedOptions().hashCode,
        equals(const AdvancedOptions().hashCode),
      );
      expect(const AdvancedOptions().copyWith(wgPort: 1194).wgPort, 1194);
      final changed = const AdvancedOptions().copyWith(mtu: 1400);
      expect(const AdvancedOptions(), isNot(equals(changed)));
    });
  });

  group('NewUserSpec', () {
    test('equality, hashCode and copyWith', () {
      const a = NewUserSpec(username: 'deploy', password: 'pw');
      const b = NewUserSpec(username: 'deploy', password: 'pw');
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a.copyWith(username: 'admin').username, 'admin');
    });
  });
}
