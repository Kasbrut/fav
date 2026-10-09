import 'package:fav/core/crypto/ed25519_keypair.dart';
import 'package:fav/features/install/application/ssh_auth_resolver.dart';
import 'package:fav/features/install/domain/ssh_client.dart';
import 'package:fav/features/monitoring/data/ssh_monitor_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_ssh_key_repository.dart';
import '../../../support/recording_ssh_client.dart';
import '../../../support/server_fakes.dart';

void main() {
  late SshAuthResolver resolver;

  setUpAll(() async {
    resolver = SshAuthResolver(
      FakeSshKeyRepository(await Ed25519KeyPair.generate()),
    );
  });

  // The repo joins the two `cat`s with this sentinel in a single round trip.
  const sentinel = '\n---WG-MONITOR-SEP---\n';

  const snapshotJson =
      '{"schemaVersion":1,"monitorVersion":"1.0.0",'
      '"generatedAt":"2026-05-22T10:00:00Z",'
      '"interface":{"publicKey":"srv_pub","listenPort":51820},'
      '"peers":[{"publicKey":"peer1","endpoint":"1.2.3.4:51820",'
      '"allowedIps":["10.13.13.2/32"],"latestHandshake":1747900000,'
      '"rx":1024,"tx":2048,"online":true}]}';

  const eventsJsonl =
      '{"serverTimestamp":"2026-05-22T09:00:00Z","publicKey":"peer1",'
      '"type":"connect","rx":10,"tx":20,"latestHandshake":1747900000}\n'
      '{"serverTimestamp":"2026-05-22T09:05:00Z","publicKey":"peer1",'
      '"type":"disconnect","rx":50,"tx":80,"latestHandshake":1747900100}';

  // Key-authenticated server, so the resolver does not require a password.
  final keyServer = testServer().copyWith(sshKeyId: 'key-1');

  SshMonitorRepository repoFor(RecordingSshClient client) =>
      SshMonitorRepository(clientFactory: () => client, authResolver: resolver);

  test('parses the snapshot and events from a single session', () async {
    final client = RecordingSshClient(
      onRun: (_) => const SshCommandResult(
        stdout: '$snapshotJson$sentinel$eventsJsonl',
        stderr: '',
        exitCode: 0,
      ),
    );

    final result = await repoFor(client).fetchAll(keyServer);

    expect(result.snapshot, isNotNull);
    expect(result.snapshot!.peers, hasLength(1));
    expect(result.snapshot!.peers.first.publicKey, 'peer1');
    expect(result.events, hasLength(2));
    expect(client.connectCount, 1);
    expect(client.closeCount, 1);
  });

  test('returns an empty result when the agent is not installed', () async {
    // Missing files => the `|| true` guard yields empty stdout.
    final client = RecordingSshClient(
      onRun: (_) => const SshCommandResult(stdout: '', stderr: '', exitCode: 0),
    );

    final result = await repoFor(client).fetchAll(keyServer);

    expect(result.snapshot, isNull);
    expect(result.events, isEmpty);
    expect(client.closeCount, 1);
  });

  test('tolerates a malformed snapshot while still parsing events', () async {
    final client = RecordingSshClient(
      onRun: (_) => const SshCommandResult(
        stdout: '{snapshot mid-write$sentinel$eventsJsonl',
        stderr: '',
        exitCode: 0,
      ),
    );

    final result = await repoFor(client).fetchAll(keyServer);

    expect(result.snapshot, isNull);
    expect(result.events, hasLength(2));
  });

  test('closes the session even when the command throws', () async {
    final client = RecordingSshClient(
      onRun: (_) => throw const SshCommandFailure(),
    );

    await expectLater(
      repoFor(client).fetchAll(keyServer),
      throwsA(isA<SshCommandFailure>()),
    );
    expect(client.closeCount, 1);
  });

  group('events tail protocol (M13)', () {
    // Every tick used to re-download and re-store the full 7-day events
    // log; the repository now fetches only the lines past the caller's
    // high-water mark, with a reset marker after a logrotate.
    SshCommandResult respond(String stdout) =>
        SshCommandResult(stdout: stdout, stderr: '', exitCode: 0);

    test('requests only the tail past the given line offset', () async {
      final client = RecordingSshClient(
        onRun: (_) => respond('$snapshotJson$sentinel$eventsJsonl'),
      );

      await repoFor(
        client,
      ).fetchAll(keyServer, eventsLineOffset: 40, eventsFileId: '8:42');

      final command = client.runCommands.single;
      expect(command, contains('tail -n +41'));
      expect(command, contains('wc -l'));
      expect(command, contains("[ '8:42' != \"\$FID\" ]"));
    });

    test('advances the offset only by the complete lines received', () async {
      // The fixture's second line has no trailing newline: it may still be
      // mid-write, so it is parsed but NOT consumed — the next tick
      // re-fetches it complete (the events box dedupes by composite key).
      final client = RecordingSshClient(
        onRun: (_) => respond(
          '$snapshotJson${sentinel}WG-EVT-CURSOR 8:42 41\n$eventsJsonl',
        ),
      );

      final result = await repoFor(
        client,
      ).fetchAll(keyServer, eventsLineOffset: 40);

      expect(result.events, hasLength(2));
      expect(result.nextEventsLineOffset, 41);
      expect(result.nextEventsFileId, '8:42');
    });

    test('a rotation cursor returns the new current-file offset', () async {
      final client = RecordingSshClient(
        onRun: (_) => respond(
          '$snapshotJson${sentinel}WG-EVT-CURSOR 8:99 1\n$eventsJsonl',
        ),
      );

      final result = await repoFor(
        client,
      ).fetchAll(keyServer, eventsLineOffset: 500);

      // The cursor line is stripped. Archived and current events still parse,
      // while the offset counts only complete lines in the current file.
      expect(result.events, hasLength(2));
      expect(result.nextEventsLineOffset, 1);
      expect(result.nextEventsFileId, '8:99');
    });

    test('initial read includes retained archives oldest first', () async {
      final client = RecordingSshClient(
        onRun: (_) => respond('$snapshotJson$sentinel$eventsJsonl'),
      );

      await repoFor(client).fetchAll(keyServer);

      final command = client.runCommands.single;
      expect(command, contains('for N in 7 6 5 4 3 2 1'));
      expect(command, contains('gzip -cd'));
      expect(command, contains("P='$kMonitorEventsPath'.\$N"));
    });

    test(
      'rejects an invalid file identity before building the command',
      () async {
        final client = RecordingSshClient(
          onRun: (_) => respond('$snapshotJson$sentinel$eventsJsonl'),
        );

        await repoFor(client).fetchAll(
          keyServer,
          eventsFileId: "8:42'; touch /tmp/untrusted; echo '",
        );

        final command = client.runCommands.single;
        expect(command, isNot(contains('/tmp/untrusted')));
        expect(command, contains("if [ '' != \"\$FID\" ]"));
      },
    );
  });

  test('fetchSnapshot and fetchEvents delegate to fetchAll', () async {
    final client = RecordingSshClient(
      onRun: (_) => const SshCommandResult(
        stdout: '$snapshotJson$sentinel$eventsJsonl',
        stderr: '',
        exitCode: 0,
      ),
    );
    final repo = repoFor(client);

    expect(await repo.fetchSnapshot(keyServer), isNotNull);
    expect(await repo.fetchEvents(keyServer), hasLength(2));
  });
}

/// Minimal throwable used to assert the session is closed on failure.
class SshCommandFailure implements Exception {
  const SshCommandFailure();
}
