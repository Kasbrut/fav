import 'package:fav/core/errors/app_exception.dart';
import 'package:fav/features/install/application/run_recovery_service.dart';
import 'package:fav/features/install/application/ssh_auth_resolver.dart';
import 'package:fav/features/install/data/keys/ssh_key_repository.dart';
import 'package:fav/features/install/domain/install_run.dart';
import 'package:fav/features/install/domain/ssh_client.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/capturing_logger.dart';
import '../../../support/in_memory_run_repository.dart';
import '../../../support/in_memory_secure_store.dart';
import '../../../support/recording_ssh_client.dart';
import '../../../support/server_fakes.dart';

void main() {
  const runningState =
      '{"run_id":"run-1","started_at":"2026-05-18T10:00:00Z",'
      '"steps":{},"warnings":[],"error":null}';

  InstallRun runningRun() => InstallRun(
    runId: 'run-1',
    serverId: 'srv-1',
    status: RunStatus.running,
    steps: const [],
    scriptWasModified: false,
    startedAt: DateTime(2026, 5, 18),
  );

  Future<FakeServerRepository> seededServers() async {
    final servers = FakeServerRepository();
    await servers.save(testServer());
    return servers;
  }

  SshCommandResult ok(String stdout) =>
      SshCommandResult(stdout: stdout, stderr: '', exitCode: 0);

  test('logs the reconnect attempt and the recovery outcome', () async {
    final output = CapturingLogOutput();
    final runs = InMemoryRunRepository();
    final client = RecordingSshClient(
      onRun: (command) => command.contains('kill -0')
          ? ok('WG-ALIVE\n')
          : ok('$runningState\n---WG-EXIT---\n'),
    );
    final service = RunRecoveryService(
      sshClientFactory: () => client,
      serverRepository: await seededServers(),
      runRepository: runs,
      authResolver: SshAuthResolver(
        SecureSshKeyRepository(InMemorySecureStore()),
      ),
      logger: capturingLogger(output),
    );

    await service.recover(localRun: runningRun(), password: 'pw');

    expect(
      output.lines,
      contains(matches(RegExp('Recovery.*run-1'))),
      reason: 'the recovery attempt must be logged with the run id',
    );
    expect(
      output.lines,
      contains(matches(RegExp('RecoveryResumePolling'))),
      reason: 'the recovery outcome must be logged',
    );
  });

  test('resumes polling when the run is still running', () async {
    final runs = InMemoryRunRepository();
    final client = RecordingSshClient(
      onRun: (command) => command.contains('kill -0')
          ? ok('WG-ALIVE\n')
          : ok('$runningState\n---WG-EXIT---\n'),
    );
    final service = RunRecoveryService(
      sshClientFactory: () => client,
      serverRepository: await seededServers(),
      runRepository: runs,
      authResolver: SshAuthResolver(
        SecureSshKeyRepository(InMemorySecureStore()),
      ),
    );

    final outcome = await service.recover(
      localRun: runningRun(),
      password: 'pw',
    );

    expect(outcome, isA<RecoveryResumePolling>());
    // The caller owns the still-open connection.
    expect(client.closeCount, 0);
  });

  test('resumes finalization when an install exit file is present', () async {
    final runs = InMemoryRunRepository();
    final client = RecordingSshClient(
      onRun: (command) => ok('$runningState\n---WG-EXIT---\n0'),
    );
    final service = RunRecoveryService(
      sshClientFactory: () => client,
      serverRepository: await seededServers(),
      runRepository: runs,
      authResolver: SshAuthResolver(
        SecureSshKeyRepository(InMemorySecureStore()),
      ),
    );

    final outcome = await service.recover(
      localRun: runningRun(),
      password: 'pw',
    );

    expect(outcome, isA<RecoveryResumePolling>());
    expect(runs.runs, isEmpty);
    expect(client.closeCount, 0);
  });

  test('reads state/pid under sudo for a non-root login (H4)', () async {
    // The state/exit/pid files are root-owned; a non-root sudoer must read them
    // under sudo, otherwise a healthy run reads as empty and is wrongly
    // orphaned. The password travels only via stdin.
    final runs = InMemoryRunRepository();
    final client = RecordingSshClient(
      onRun: (command) => command.contains('kill -0')
          ? ok('WG-ALIVE\n')
          : ok('$runningState\n---WG-EXIT---\n'),
    );
    final servers = FakeServerRepository();
    await servers.save(testServer(username: 'deploy'));
    final service = RunRecoveryService(
      sshClientFactory: () => client,
      serverRepository: servers,
      runRepository: runs,
      authResolver: SshAuthResolver(
        SecureSshKeyRepository(InMemorySecureStore()),
      ),
    );

    final outcome = await service.recover(
      localRun: runningRun(),
      password: 'sudopw',
    );

    expect(outcome, isA<RecoveryResumePolling>());
    expect(client.runCommands.every((c) => c.contains('sudo -S')), isTrue);
    for (final c in client.runCommands) {
      expect(c.contains('sudopw'), isFalse);
    }
    expect(
      client.runStdins.any((s) => s?.contains('sudopw') ?? false),
      isTrue,
    );
  });

  test('preserves install secrets until resumed finalization (H4)', () async {
    // A run that finished while the app was away leaves client.conf (client
    // private key + PSK) in the run dir. Recovery must wipe it.
    final runs = InMemoryRunRepository();
    final client = RecordingSshClient(
      onRun: (command) => ok('$runningState\n---WG-EXIT---\n0'),
    );
    final service = RunRecoveryService(
      sshClientFactory: () => client,
      serverRepository: await seededServers(),
      runRepository: runs,
      authResolver: SshAuthResolver(
        SecureSshKeyRepository(InMemorySecureStore()),
      ),
    );

    final outcome = await service.recover(
      localRun: runningRun(),
      password: 'pw',
    );

    expect(outcome, isA<RecoveryResumePolling>());
    expect(
      client.runCommands.any(
        (c) => c.contains('rm -rf') && c.contains('/opt/wg-installer/run-1'),
      ),
      isFalse,
    );
  });

  test('orphans the run when the state file is gone', () async {
    final runs = InMemoryRunRepository();
    final client = RecordingSshClient(
      onRun: (command) => ok('---WG-EXIT---\n'),
    );
    final service = RunRecoveryService(
      sshClientFactory: () => client,
      serverRepository: await seededServers(),
      runRepository: runs,
      authResolver: SshAuthResolver(
        SecureSshKeyRepository(InMemorySecureStore()),
      ),
    );

    final outcome = await service.recover(
      localRun: runningRun(),
      password: 'pw',
    );

    expect(outcome, isA<RecoveryOrphaned>());
    expect(runs.runs.single.status, RunStatus.orphaned);
  });

  test('orphans the run when the installer process is dead', () async {
    final runs = InMemoryRunRepository();
    final client = RecordingSshClient(
      onRun: (command) => command.contains('kill -0')
          ? const SshCommandResult(stdout: '', stderr: '', exitCode: 1)
          : ok('$runningState\n---WG-EXIT---\n'),
    );
    final service = RunRecoveryService(
      sshClientFactory: () => client,
      serverRepository: await seededServers(),
      runRepository: runs,
      authResolver: SshAuthResolver(
        SecureSshKeyRepository(InMemorySecureStore()),
      ),
    );

    final outcome = await service.recover(
      localRun: runningRun(),
      password: 'pw',
    );

    expect(outcome, isA<RecoveryOrphaned>());
  });

  test('fails when the connection cannot be established', () async {
    final runs = InMemoryRunRepository();
    final client = RecordingSshClient(
      onConnect: () => throw const AppException(ErrorCode.connHostUnreachable),
    );
    final service = RunRecoveryService(
      sshClientFactory: () => client,
      serverRepository: await seededServers(),
      runRepository: runs,
      authResolver: SshAuthResolver(
        SecureSshKeyRepository(InMemorySecureStore()),
      ),
    );

    final outcome = await service.recover(
      localRun: runningRun(),
      password: 'pw',
    );

    expect(outcome, isA<RecoveryFailed>());
    expect(
      (outcome as RecoveryFailed).error.code,
      ErrorCode.connHostUnreachable,
    );
  });

  // Run recovery is deliberately run-type-agnostic: no production path creates
  // a RunType.teardown run today (teardown is synchronous via sudo), but a
  // future detached teardown should recover through the same machinery. This
  // guards that the recovery path treats a teardown-typed run exactly like an
  // install one.
  test('recovers a completed teardown run (RunType.teardown)', () async {
    final runs = InMemoryRunRepository();
    final client = RecordingSshClient(
      onRun: (command) => ok('$runningState\n---WG-EXIT---\n0'),
    );
    final service = RunRecoveryService(
      sshClientFactory: () => client,
      serverRepository: await seededServers(),
      runRepository: runs,
      authResolver: SshAuthResolver(
        SecureSshKeyRepository(InMemorySecureStore()),
      ),
    );

    final teardownRun = InstallRun(
      runId: 'run-1',
      serverId: 'srv-1',
      status: RunStatus.running,
      steps: const [],
      scriptWasModified: false,
      startedAt: DateTime(2026, 5, 18),
      runType: RunType.teardown,
    );

    final outcome = await service.recover(
      localRun: teardownRun,
      password: 'pw',
    );

    expect(outcome, isA<RecoveryCompleted>());
    expect((outcome as RecoveryCompleted).run.status, RunStatus.success);
    expect(runs.runs.single.status, RunStatus.success);
    expect(client.closeCount, greaterThan(0));
  });
}
