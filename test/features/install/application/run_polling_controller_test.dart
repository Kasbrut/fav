import 'dart:async';

import 'package:fav/core/errors/app_exception.dart';
import 'package:fav/core/utils/app_logger.dart';
import 'package:fav/features/install/application/run_polling_controller.dart';
import 'package:fav/features/install/data/hive_run_repository.dart';
import 'package:fav/features/install/domain/install_run.dart';
import 'package:fav/features/install/domain/run_paths.dart';
import 'package:fav/features/install/domain/ssh_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/capturing_logger.dart';
import '../../../support/in_memory_run_repository.dart';
import '../../../support/recording_ssh_client.dart';

void main() {
  const paths = RunPaths('run-1');
  const fastInterval = Duration(milliseconds: 1);

  InstallRun baseRun() => InstallRun(
    runId: 'run-1',
    serverId: 'srv-1',
    status: RunStatus.running,
    steps: const [],
    scriptWasModified: false,
    startedAt: DateTime(2026, 5, 18),
  );

  ProviderContainer makeContainer(InMemoryRunRepository runs) {
    final container = ProviderContainer(
      overrides: [runRepositoryProvider.overrideWithValue(runs)],
    );
    addTearDown(container.dispose);
    // An active listener keeps the autoDispose controller alive.
    container.listen(runPollingControllerProvider, (_, _) {});
    return container;
  }

  SshCommandResult poll(String state, String exit) => SshCommandResult(
    stdout: '$state\n---WG-EXIT---\n$exit',
    stderr: '',
    exitCode: 0,
  );

  const runningState =
      '{"run_id":"run-1","started_at":"2026-05-18T10:00:00Z",'
      '"steps":{"probe":{"status":"done"}},"warnings":[],"error":null}';

  test(
    'a second start closes the offered client instead of leaking (M2)',
    () async {
      final runs = InMemoryRunRepository();
      final container = makeContainer(runs);
      final notifier = container.read(runPollingControllerProvider.notifier);

      // First session: never produces an exit file, so the loop keeps going.
      final first = RecordingSshClient(
        onRun: (command) => poll(runningState, ''),
      );
      unawaited(
        notifier.start(
          client: first,
          run: baseRun(),
          paths: paths,
          pollInterval: fastInterval,
          maxBackoff: fastInterval,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // A second start is refused — but its borrowed client must be released,
      // not silently leaked (the caller handed over ownership).
      final second = RecordingSshClient();
      await notifier.start(client: second, run: baseRun(), paths: paths);
      expect(second.closeCount, 1);
      expect(second.runCommands, isEmpty);

      notifier.stop();
    },
  );

  test('logs the polled step changes and the final outcome', () async {
    final output = CapturingLogOutput();
    final runs = InMemoryRunRepository();
    final container = ProviderContainer(
      overrides: [
        runRepositoryProvider.overrideWithValue(runs),
        loggerProvider.overrideWithValue(capturingLogger(output)),
      ],
    );
    addTearDown(container.dispose);
    container.listen(runPollingControllerProvider, (_, _) {});
    var calls = 0;
    final client = RecordingSshClient(
      onRun: (command) {
        calls++;
        return poll(runningState, calls >= 2 ? '0' : '');
      },
    );

    await container
        .read(runPollingControllerProvider.notifier)
        .start(
          client: client,
          run: baseRun(),
          paths: paths,
          pollInterval: fastInterval,
          maxBackoff: fastInterval,
        );

    expect(
      output.lines,
      contains(matches(RegExp('run-1.*probe.*done'))),
      reason: 'a step change must be logged',
    );
    expect(
      output.lines,
      contains(matches(RegExp('run-1.*exit 0'))),
      reason: 'the terminal outcome must be logged',
    );
  });

  test('reaches success when the exit file reports 0', () async {
    final runs = InMemoryRunRepository();
    final container = makeContainer(runs);
    var calls = 0;
    final client = RecordingSshClient(
      onRun: (command) {
        calls++;
        return poll(runningState, calls >= 2 ? '0' : '');
      },
    );

    await container
        .read(runPollingControllerProvider.notifier)
        .start(
          client: client,
          run: baseRun(),
          paths: paths,
          pollInterval: fastInterval,
          maxBackoff: fastInterval,
        );

    final state = container.read(runPollingControllerProvider);
    expect(state.isTerminal, isTrue);
    expect(state.run?.status, RunStatus.success);
    expect(state.error, isNull);
    expect(client.closeCount, greaterThan(0));
  });

  test('reads the state/exit files under sudo for a non-root login', () async {
    final runs = InMemoryRunRepository();
    final container = makeContainer(runs);
    var calls = 0;
    final client = RecordingSshClient(
      onRun: (command) {
        calls++;
        return poll(runningState, calls >= 2 ? '0' : '');
      },
    );

    await container
        .read(runPollingControllerProvider.notifier)
        .start(
          client: client,
          run: baseRun(),
          paths: paths,
          sudoPassword: 's3cret-poll',
          pollInterval: fastInterval,
          maxBackoff: fastInterval,
        );

    final state = container.read(runPollingControllerProvider);
    expect(state.run?.status, RunStatus.success);
    // Reads go through sudo; the password travels only via stdin.
    expect(client.runCommands.every((c) => c.contains('sudo -S')), isTrue);
    for (final c in client.runCommands) {
      expect(c.contains('s3cret-poll'), isFalse);
    }
    expect(
      client.runStdins.any((s) => s?.contains('s3cret-poll') ?? false),
      isTrue,
    );
  });

  test('fails the run when the exit file reports non-zero', () async {
    final runs = InMemoryRunRepository();
    final container = makeContainer(runs);
    final client = RecordingSshClient(
      onRun: (command) => poll(runningState, '1'),
    );

    await container
        .read(runPollingControllerProvider.notifier)
        .start(
          client: client,
          run: baseRun(),
          paths: paths,
          pollInterval: fastInterval,
        );

    final state = container.read(runPollingControllerProvider);
    expect(state.run?.status, RunStatus.failed);
    expect(state.error?.code, ErrorCode.runStepFailed);
    expect(runs.runs.single.status, RunStatus.failed);
  });

  test('times out after the failure budget is exhausted', () async {
    final runs = InMemoryRunRepository();
    final container = makeContainer(runs);
    final client = RecordingSshClient(
      onRun: (command) => throw Exception('connection lost'),
    );

    await container
        .read(runPollingControllerProvider.notifier)
        .start(
          client: client,
          run: baseRun(),
          paths: paths,
          pollInterval: fastInterval,
          maxBackoff: fastInterval,
          maxConsecutiveFailures: 3,
        );

    final state = container.read(runPollingControllerProvider);
    expect(state.isTerminal, isTrue);
    expect(state.error?.code, ErrorCode.pollingTimeout);
  });

  test('reconnects after a transport failure and completes', () async {
    final runs = InMemoryRunRepository();
    final container = makeContainer(runs);
    final broken = RecordingSshClient(
      onRun: (_) => throw StateError('connection lost'),
    );
    final replacement = RecordingSshClient(
      onRun: (_) => poll(runningState, '0'),
    );
    var reconnects = 0;

    await container
        .read(runPollingControllerProvider.notifier)
        .start(
          client: broken,
          run: baseRun(),
          paths: paths,
          reconnect: () async {
            reconnects++;
            return replacement;
          },
          pollInterval: fastInterval,
          maxBackoff: fastInterval,
        );

    final state = container.read(runPollingControllerProvider);
    expect(reconnects, 1);
    expect(broken.closeCount, greaterThan(0));
    expect(state.run?.status, RunStatus.success);
    expect(state.connectionLost, isFalse);
  });

  test('a hung poll read times out and ends the loop (H5)', () async {
    // A black-holed connection leaves `run` awaiting forever. Without a read
    // timeout the loop would hang; with it, each hung read counts as a failure
    // until the budget is exhausted and polling ends with pollingTimeout.
    final runs = InMemoryRunRepository();
    final container = makeContainer(runs);
    final client = RecordingSshClient(
      // Never completes — simulates a silent network drop mid-read.
      onRun: (command) => Completer<SshCommandResult>().future,
    );

    await container
        .read(runPollingControllerProvider.notifier)
        .start(
          client: client,
          run: baseRun(),
          paths: paths,
          pollInterval: fastInterval,
          maxBackoff: fastInterval,
          maxConsecutiveFailures: 2,
          pollReadTimeout: const Duration(milliseconds: 20),
        );

    final state = container.read(runPollingControllerProvider);
    expect(state.isTerminal, isTrue);
    expect(state.error?.code, ErrorCode.pollingTimeout);
  });

  test('a soft miss keeps polling until the run completes', () async {
    final runs = InMemoryRunRepository();
    final container = makeContainer(runs);
    var calls = 0;
    final client = RecordingSshClient(
      onRun: (command) {
        calls++;
        // First poll catches the state file mid-write (malformed).
        return calls == 1 ? poll('{partial', '') : poll(runningState, '0');
      },
    );

    await container
        .read(runPollingControllerProvider.notifier)
        .start(
          client: client,
          run: baseRun(),
          paths: paths,
          pollInterval: fastInterval,
        );

    final state = container.read(runPollingControllerProvider);
    expect(state.isTerminal, isTrue);
    expect(state.run?.status, RunStatus.success);
  });
  test(
    'unavailable state exhausts the retry budget instead of polling forever',
    () async {
      final runs = InMemoryRunRepository();
      final container = makeContainer(runs);
      final client = RecordingSshClient(
        onRun: (_) => poll('', ''),
      );
      await container
          .read(runPollingControllerProvider.notifier)
          .start(
            client: client,
            run: baseRun(),
            paths: paths,
            pollInterval: fastInterval,
            maxBackoff: fastInterval,
            maxConsecutiveFailures: 2,
          );
      expect(client.runCommands, hasLength(2));
      expect(
        container.read(runPollingControllerProvider).error?.code,
        ErrorCode.pollingTimeout,
      );
      expect(client.closeCount, 1);
    },
  );
}
