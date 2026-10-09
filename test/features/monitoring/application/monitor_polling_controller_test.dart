import 'package:fav/core/crypto/ed25519_keypair.dart';
import 'package:fav/core/errors/app_exception.dart';
import 'package:fav/features/install/application/ssh_auth_resolver.dart';
import 'package:fav/features/monitoring/application/monitor_polling_controller.dart';
import 'package:fav/features/monitoring/data/peers_state_parser.dart';
import 'package:fav/features/monitoring/data/ssh_monitor_repository.dart';
import 'package:fav/features/monitoring/domain/client_live_status.dart';
import 'package:fav/features/monitoring/domain/monitor_repository.dart';
import 'package:fav/features/monitoring/domain/peer_event.dart';
import 'package:fav/features/monitoring/domain/peer_snapshot.dart';
import 'package:fav/features/servers/data/hive_server_repository.dart';
import 'package:fav/features/servers/domain/server.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_ssh_key_repository.dart';
import '../../../support/recording_ssh_client.dart';
import '../../../support/server_fakes.dart';

/// In-memory [MonitorRepository] that returns fixed data or throws.
class _FakeMonitorRepository implements MonitorRepository {
  _FakeMonitorRepository({this.snapshot, this.error});

  final PeersStateSnapshot? snapshot;
  final Exception? error;

  @override
  Future<PeersStateSnapshot?> fetchSnapshot(Server server) async {
    final failure = error;
    if (failure != null) throw failure;
    return snapshot;
  }

  @override
  Future<List<PeerEvent>> fetchEvents(Server server) async {
    final failure = error;
    if (failure != null) throw failure;
    return const [];
  }
}

/// [SshMonitorRepository] double recording the offset each tick passes in.
class _RecordingTailRepository extends SshMonitorRepository {
  _RecordingTailRepository({
    required super.clientFactory,
    required super.authResolver,
    required this.snapshot,
  });

  final PeersStateSnapshot? snapshot;
  final List<int> offsets = [];
  final List<String?> fileIds = [];

  @override
  Future<MonitorReadResult> fetchAll(
    Server server, {
    int eventsLineOffset = 0,
    String? eventsFileId,
  }) async {
    offsets.add(eventsLineOffset);
    fileIds.add(eventsFileId);
    return MonitorReadResult(
      snapshot: snapshot,
      events: const [],
      nextEventsLineOffset: eventsLineOffset + 7,
      nextEventsFileId: '8:42',
    );
  }
}

void main() {
  const snapshotJson =
      '{"schemaVersion":1,"monitorVersion":"1.0.0",'
      '"generatedAt":"2026-05-22T10:00:00Z",'
      '"interface":{"publicKey":"srv_pub","listenPort":51820},"peers":[]}';

  PeersStateSnapshot sampleSnapshot() =>
      const PeersStateParser().tryParse(snapshotJson)!;

  ProviderContainer makeContainer({
    required MonitorRepository repo,
    required FakeServerRepository servers,
  }) {
    final container = ProviderContainer(
      overrides: [
        monitorRepositoryProvider.overrideWithValue(repo),
        serverRepositoryProvider.overrideWithValue(servers),
      ],
    );
    addTearDown(container.dispose);
    // Keep the autoDispose family notifier alive for the test.
    container.listen(monitorPollingControllerProvider('srv-1'), (_, _) {});
    return container;
  }

  MonitorPollingState read(ProviderContainer c) =>
      c.read(monitorPollingControllerProvider('srv-1'));

  testWidgets('passes the advancing high-water mark to fetchAll (M13)', (
    tester,
  ) async {
    final servers = FakeServerRepository();
    await servers.save(testServer());
    final repo = _RecordingTailRepository(
      clientFactory: RecordingSshClient.new,
      authResolver: SshAuthResolver(
        FakeSshKeyRepository(await Ed25519KeyPair.generate()),
      ),
      snapshot: sampleSnapshot(),
    );
    // Built inline (not via makeContainer) so the container can be disposed
    // inside the test body — the poll timer must be gone before the
    // pending-timer check at the end of a widget test.
    final container = ProviderContainer(
      overrides: [
        monitorRepositoryProvider.overrideWithValue(repo),
        serverRepositoryProvider.overrideWithValue(servers),
      ],
    )..listen(monitorPollingControllerProvider('srv-1'), (_, _) {});
    // The first (deferred, zero-delay) poll starts from zero. Fake timers
    // fire on clock advance, so pump a nonzero duration.
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump(const Duration(milliseconds: 1));
    expect(repo.offsets, [0]);
    expect(repo.fileIds, [null]);

    // …and each following tick resumes from the returned high-water mark.
    await tester.pump(kMonitorPollInterval);
    await tester.pump(const Duration(milliseconds: 1));
    expect(repo.offsets, [0, 7]);
    expect(repo.fileIds, [null, '8:42']);

    container.dispose();
  });

  test('stores the snapshot after a successful poll', () async {
    final servers = FakeServerRepository();
    await servers.save(testServer());
    final container = makeContainer(
      repo: _FakeMonitorRepository(snapshot: sampleSnapshot()),
      servers: servers,
    );

    await pumpEventQueue();

    final state = read(container);
    expect(state.snapshot, isNotNull);
    expect(state.consecutiveFailures, 0);
    expect(state.lastError, isNull);
  });

  test('flags the server-not-found case as not-installed', () async {
    final container = makeContainer(
      repo: _FakeMonitorRepository(),
      servers: FakeServerRepository(), // empty: server lookup returns null
    );

    await pumpEventQueue();

    final state = read(container);
    expect(state.lastErrorReason, ClientLiveStatusUnknownReason.notInstalled);
    expect(state.consecutiveFailures, 1);
    expect(state.lastError, isNotNull);
  });

  test('records an SSH failure and classifies it as sshDown', () async {
    final servers = FakeServerRepository();
    await servers.save(testServer());
    final container = makeContainer(
      repo: _FakeMonitorRepository(
        error: const AppException(ErrorCode.connHostUnreachable),
      ),
      servers: servers,
    );

    await pumpEventQueue();

    final state = read(container);
    expect(state.lastError?.code, ErrorCode.connHostUnreachable);
    expect(state.lastErrorReason, ClientLiveStatusUnknownReason.sshDown);
    expect(state.consecutiveFailures, 1);
  });

  test(
    'treats a missing snapshot file as not-installed, not an error',
    () async {
      final servers = FakeServerRepository();
      await servers.save(testServer());
      final container = makeContainer(
        repo: _FakeMonitorRepository(), // snapshot null, no throw
        servers: servers,
      );

      await pumpEventQueue();

      final state = read(container);
      expect(state.snapshot, isNull);
      expect(state.lastErrorReason, ClientLiveStatusUnknownReason.notInstalled);
      expect(state.consecutiveFailures, 0);
      expect(state.lastError, isNull);
    },
  );
}
