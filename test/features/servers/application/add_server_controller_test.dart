import 'package:fav/core/errors/app_exception.dart';
import 'package:fav/features/install/data/ssh/dart_ssh_client.dart';
import 'package:fav/features/install/data/ssh/host_key_store.dart';
import 'package:fav/features/install/domain/ssh_client.dart';
import 'package:fav/features/servers/application/add_server_controller.dart';
import 'package:fav/features/servers/data/hive_server_repository.dart';
import 'package:fav/features/servers/data/server_probe.dart';
import 'package:fav/features/servers/domain/host_key_fingerprint.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/in_memory_secure_store.dart';
import '../../../support/server_fakes.dart';

/// Tests for [AddServerController].
void main() {
  const params = SshConnectionParams(
    host: '203.0.113.5',
    port: 22,
    username: 'root',
    password: 'secret',
  );

  HostKeyFingerprint fingerprint() => HostKeyFingerprint(
    host: '203.0.113.5',
    port: 22,
    keyType: 'ssh-ed25519',
    hashAlgorithm: 'md5',
    fingerprint: 'aa:bb:cc',
    pinnedAt: DateTime(2026, 5, 18),
  );

  ProviderContainer makeContainer({
    Exception? connectError,
    FakeServerRepository? repository,
  }) {
    final container = ProviderContainer(
      overrides: [
        sshClientFactoryProvider.overrideWithValue(
          () => StubSshClient(connectError: connectError),
        ),
        serverProbeProvider.overrideWithValue(
          StubServerProbe(metadata: testMetadata()),
        ),
        serverRepositoryProvider.overrideWithValue(
          repository ?? FakeServerRepository(),
        ),
        hostKeyStoreProvider.overrideWithValue(
          HostKeyStore(InMemorySecureStore()),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('a successful flow saves the server and reports success', () async {
    final repository = FakeServerRepository();
    final container = makeContainer(repository: repository);

    await container
        .read(addServerControllerProvider.notifier)
        .submit(label: 'vps', params: params);

    expect(
      container.read(addServerControllerProvider),
      isA<AddServerSuccess>(),
    );
    expect(await repository.getAll(), hasLength(1));
  });

  test('re-adding the same host:port:user updates in place (M1)', () async {
    // Retrying a failed install re-runs the add flow with the same endpoint.
    // It must reuse the existing record instead of stacking a duplicate.
    final repository = FakeServerRepository();
    final container = makeContainer(repository: repository);
    final controller = container.read(addServerControllerProvider.notifier);

    await controller.submit(label: 'vps', params: params);
    final firstId = (await repository.getAll()).single.id;
    await controller.submit(label: 'vps-renamed', params: params);

    final all = await repository.getAll();
    expect(all, hasLength(1));
    expect(all.single.id, firstId);
    expect(all.single.label, 'vps-renamed');
  });

  test('a connection error yields a failure state', () async {
    final container = makeContainer(
      connectError: const AppException(ErrorCode.authInvalidCredentials),
    );

    await container
        .read(addServerControllerProvider.notifier)
        .submit(label: 'vps', params: params);

    final state = container.read(addServerControllerProvider);
    expect(state, isA<AddServerFailure>());
    expect((state as AddServerFailure).code, ErrorCode.authInvalidCredentials);
  });

  test('an unknown host key yields the host-key-pending state', () async {
    final container = makeContainer(
      connectError: HostKeyUnknownException(fingerprint()),
    );

    await container
        .read(addServerControllerProvider.notifier)
        .submit(label: 'vps', params: params);

    expect(
      container.read(addServerControllerProvider),
      isA<AddServerHostKeyPending>(),
    );
  });

  test('confirmHostKey pins the fingerprint', () async {
    final container = makeContainer(
      connectError: HostKeyUnknownException(fingerprint()),
    );
    final controller = container.read(addServerControllerProvider.notifier);
    await controller.submit(label: 'vps', params: params);

    await controller.confirmHostKey();

    final pinned = await container
        .read(hostKeyStoreProvider)
        .lookup('203.0.113.5', 22);
    expect(pinned, equals(fingerprint()));
  });

  test('cancelHostKey returns to the editing state', () async {
    final container = makeContainer(
      connectError: HostKeyUnknownException(fingerprint()),
    );
    final controller = container.read(addServerControllerProvider.notifier);
    await controller.submit(label: 'vps', params: params);

    controller.cancelHostKey();

    expect(
      container.read(addServerControllerProvider),
      isA<AddServerEditing>(),
    );
  });
}
