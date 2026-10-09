import 'package:fav/core/persistence/secure_store.dart';
import 'package:fav/features/install/data/keys/ssh_key_repository.dart';
import 'package:fav/features/install/data/scripts/script_integrity.dart';
import 'package:fav/features/install/data/ssh/dart_ssh_client.dart';
import 'package:fav/features/install/domain/script_source.dart';
import 'package:fav/features/install/domain/ssh_client.dart';
import 'package:fav/features/servers/application/server_teardown_controller.dart';
import 'package:fav/features/servers/data/hive_server_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/in_memory_secure_store.dart';
import '../../../support/recording_ssh_client.dart';
import '../../../support/server_fakes.dart';

// The services teardown now runs synchronously over the open connection
// (staged in /tmp, run via sudo), so it is drivable with RecordingSshClient.
// These tests cover: the guard-refusal path (refuses before connecting), the
// reopen-only happy path, and the services happy path.

// A fake server where the services teardown succeeds: the staging command
// echoes WG-TRD-STAGED and the orchestrator prints WG-TRD-OK. Success is keyed
// off these stdout markers, not the SSH exit code.
SshCommandResult _servicesOk(String c) {
  if (c.contains('teardown_wireguard.sh')) {
    return const SshCommandResult(
      stdout: 'WG-TRD-OK\n',
      stderr: '',
      exitCode: 0,
    );
  }
  if (c.contains('mkdir')) {
    return const SshCommandResult(
      stdout: 'WG-TRD-STAGED\n',
      stderr: '',
      exitCode: 0,
    );
  }
  return const SshCommandResult(stdout: '', stderr: '', exitCode: 0);
}

void main() {
  ProviderContainer makeContainer(
    RecordingSshClient client,
    FakeServerRepository repo, {
    ScriptBundle? bundle,
  }) {
    final container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        serverRepositoryProvider.overrideWithValue(repo),
        secureStoreProvider.overrideWithValue(InMemorySecureStore()),
        sshClientFactoryProvider.overrideWithValue(() => client),
        bootIntegrityProvider.overrideWith(
          (ref) => bundle ?? fakeReopenBundle(),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.listen(serverTeardownControllerProvider, (_, _) {});
    return container;
  }

  test('refuses with a lockout-risk state when the guard trips', () async {
    // Server: hardened, app key present, no own keys, reopenSsh=false.
    final repo = FakeServerRepository();
    final server = hardenedServerWithAppKey();
    await repo.save(server);
    final client = RecordingSshClient();
    final container = makeContainer(client, repo);

    await container
        .read(serverTeardownControllerProvider.notifier)
        .teardown(
          server: server,
          removeServices: true,
          reopenSsh: false,
          password: 'pw',
        );

    expect(
      container.read(serverTeardownControllerProvider),
      isA<TeardownLockoutRisk>(),
    );
    // It did not connect, and the local record is untouched.
    expect(client.connectCount, 0);
    expect(await repo.getById(server.id), isNotNull);
  });

  test('local-only removal never opens an SSH connection', () async {
    final repo = FakeServerRepository();
    final server = testServer();
    await repo.save(server);
    final client = RecordingSshClient();
    final container = makeContainer(client, repo);

    await container
        .read(serverTeardownControllerProvider.notifier)
        .removeLocally(server);

    expect(client.connectCount, 0);
    expect(await repo.getById(server.id), isNull);
    expect(
      container.read(serverTeardownControllerProvider),
      isA<TeardownDone>(),
    );
  });

  test(
    'reopen-only flow re-opens SSH then removes the app key and cleans up',
    () async {
      final repo = FakeServerRepository();
      final server = hardenedServerWithAppKey(
        ownKeys: const ['ssh-ed25519 own u'],
      );
      await repo.save(server);
      final client = RecordingSshClient(
        onRun: (c) => c.contains('bash') && c.contains('wg-rvt')
            ? const SshCommandResult(
                stdout: 'WG-RVT-OK\n',
                stderr: '',
                exitCode: 0,
              )
            : const SshCommandResult(stdout: '', stderr: '', exitCode: 0),
      );
      final container = makeContainer(client, repo);
      // The server is key-only (sshKeyId set): seed the stored key so auth
      // resolves and the app-key removal can look it up.
      await container
          .read(sshKeyRepositoryProvider)
          .getOrCreate(serverId: server.sshKeyId!, comment: 'fav@${server.id}');

      await container
          .read(serverTeardownControllerProvider.notifier)
          .teardown(
            server: server,
            removeServices: false,
            reopenSsh: true,
            password: 'pw',
          );

      expect(
        container.read(serverTeardownControllerProvider),
        isA<TeardownDone>(),
      );
      expect(client.connectCount, 1);
      // Local cleanup happened only after the remote steps succeeded.
      expect(await repo.getById(server.id), isNull);
    },
  );

  test(
    'services flow runs the teardown then removes the app key and cleans up',
    () async {
      final repo = FakeServerRepository();
      // Own keys present so the lockout guard does not trip with reopen=false.
      final server = hardenedServerWithAppKey(
        ownKeys: const ['ssh-ed25519 own u'],
      );
      await repo.save(server);
      // Every command (including the teardown bash run) succeeds.
      final client = RecordingSshClient(onRun: _servicesOk);
      final container = makeContainer(
        client,
        repo,
        bundle: fakeTeardownBundle(),
      );
      await container
          .read(sshKeyRepositoryProvider)
          .getOrCreate(serverId: server.sshKeyId!, comment: 'fav@${server.id}');

      await container
          .read(serverTeardownControllerProvider.notifier)
          .teardown(
            server: server,
            removeServices: true,
            reopenSsh: false,
            password: 'pw',
          );

      expect(
        container.read(serverTeardownControllerProvider),
        isA<TeardownDone>(),
      );
      expect(client.connectCount, 1);
      // The teardown ran via sudo and staged under /tmp (non-root sudoer).
      expect(
        client.runCommands.any(
          (c) =>
              c.contains('teardown_wireguard.sh') && c.startsWith('sudo -S '),
        ),
        isTrue,
      );
      // Staging stays in /tmp; the F3 sweep is the only command that may
      // reference /opt/wg-installer.
      for (final c in client.runCommands.where((c) => c.contains('wg-trd-'))) {
        expect(c.contains('/opt/'), isFalse, reason: 'staging stays in /tmp');
      }
      expect(await repo.getById(server.id), isNull);
    },
  );

  test(
    'removes the app key LAST — after the services teardown command',
    () async {
      final repo = FakeServerRepository();
      final server = hardenedServerWithAppKey(
        ownKeys: const ['ssh-ed25519 own u'],
      );
      await repo.save(server);
      final client = RecordingSshClient(onRun: _servicesOk);
      final container = makeContainer(
        client,
        repo,
        bundle: fakeTeardownBundle(),
      );
      await container
          .read(sshKeyRepositoryProvider)
          .getOrCreate(serverId: server.sshKeyId!, comment: 'fav@${server.id}');

      await container
          .read(serverTeardownControllerProvider.notifier)
          .teardown(
            server: server,
            removeServices: true,
            reopenSsh: false,
            password: 'pw',
          );

      // The connection authenticates with the app key, so revoking it must be
      // the very last remote command — after the services teardown has run.
      final teardownIndex = client.runCommands.indexWhere(
        (c) => c.contains('teardown_wireguard.sh') && c.startsWith('sudo -S '),
      );
      final appKeyIndex = client.runCommands.indexWhere(
        (c) => c.contains('authorized_keys') && c.contains('grep -vxF'),
      );
      expect(teardownIndex, greaterThanOrEqualTo(0));
      expect(appKeyIndex, greaterThan(teardownIndex));
    },
  );

  test(
    'services abort leaves the local record intact and never removes the key',
    () async {
      final repo = FakeServerRepository();
      final server = hardenedServerWithAppKey(
        ownKeys: const ['ssh-ed25519 own u'],
      );
      await repo.save(server);
      // The teardown orchestrator run fails (non-zero exit); everything else
      // (staging, uploads, cleanup) succeeds.
      final client = RecordingSshClient(
        onRun: (c) =>
            c.contains('teardown_wireguard.sh') && c.startsWith('sudo -S ')
            ? const SshCommandResult(
                stdout: '',
                stderr: 'module 30_remove_firewall failed',
                exitCode: 1,
              )
            : const SshCommandResult(stdout: '', stderr: '', exitCode: 0),
      );
      final container = makeContainer(
        client,
        repo,
        bundle: fakeTeardownBundle(),
      );
      await container
          .read(sshKeyRepositoryProvider)
          .getOrCreate(serverId: server.sshKeyId!, comment: 'fav@${server.id}');

      await container
          .read(serverTeardownControllerProvider.notifier)
          .teardown(
            server: server,
            removeServices: true,
            reopenSsh: false,
            password: 'pw',
          );

      expect(
        container.read(serverTeardownControllerProvider),
        isA<TeardownFailure>(),
      );
      // The local record survives so the user can retry or remove-locally.
      expect(await repo.getById(server.id), isNotNull);
      // The app key — our only way back in — was NOT revoked.
      expect(
        client.runCommands.any(
          (c) => c.contains('authorized_keys') && c.contains('grep -vxF'),
        ),
        isFalse,
      );
    },
  );
}
