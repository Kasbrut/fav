import 'package:fav/core/crypto/ed25519_keypair.dart';
import 'package:fav/core/errors/app_exception.dart';
import 'package:fav/core/utils/app_logger.dart';
import 'package:fav/features/install/application/ssh_auth_resolver.dart';
import 'package:fav/features/install/data/keys/ssh_key_repository.dart';
import 'package:fav/features/install/data/ssh/dart_ssh_client.dart';
import 'package:fav/features/servers/data/hive_server_repository.dart';
import 'package:fav/features/shell/application/ssh_shell_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';

import '../../../support/capturing_logger.dart';
import '../../../support/fake_ssh_client.dart';
import '../../../support/server_fakes.dart';

/// Key repository that must never be consulted for a password-auth server.
class _UnusedKeyRepository implements SshKeyRepository {
  @override
  Future<Ed25519KeyPair?> get(String serverId) =>
      throw UnimplementedError('key repo should not be used');

  @override
  Future<Ed25519KeyPair> getOrCreate({
    required String serverId,
    required String comment,
  }) => throw UnimplementedError('key repo should not be used');

  @override
  Future<void> delete(String serverId) async {}
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  Future<ProviderContainer> makeContainer(
    FakeSshClient client, {
    Logger? logger,
  }) async {
    final servers = FakeServerRepository();
    await servers.save(testServer());
    final container = ProviderContainer(
      overrides: [
        serverRepositoryProvider.overrideWithValue(servers),
        sshAuthResolverProvider.overrideWithValue(
          SshAuthResolver(_UnusedKeyRepository()),
        ),
        sshClientFactoryProvider.overrideWithValue(() => client),
        if (logger != null) loggerProvider.overrideWithValue(logger),
      ],
    );
    addTearDown(container.dispose);
    // Keep the autoDispose family notifier alive for the test.
    container.listen(sshShellControllerProvider('srv-1'), (_, _) {});
    return container;
  }

  SshShellState read(ProviderContainer c) =>
      c.read(sshShellControllerProvider('srv-1'));

  SshShellController notifier(ProviderContainer c) =>
      c.read(sshShellControllerProvider('srv-1').notifier);

  test('starts in the connecting state', () async {
    final container = await makeContainer(FakeSshClient(const {}));
    expect(read(container), isA<SshShellConnecting>());
  });

  test('logs a failure with its error code', () async {
    final output = CapturingLogOutput();
    final container = await makeContainer(
      FakeSshClient(
        const {},
        connectError: const AppException(ErrorCode.connHostUnreachable),
      ),
      logger: capturingLogger(output),
    );
    await notifier(container).start(password: 'pw');
    await _settle();

    expect(
      output.lines,
      contains(matches(RegExp('SSH shell failed.*connHostUnreachable'))),
    );
  });

  test('connects and exposes the live session', () async {
    final client = FakeSshClient(const {});
    final container = await makeContainer(client);
    await notifier(container).start(password: 'pw');
    final state = read(container);
    expect(state, isA<SshShellConnected>());
    expect((state as SshShellConnected).session, same(client.shellSession));
    expect(client.connectCount, 1);
  });

  test('a connect failure maps to an error state', () async {
    final client = FakeSshClient(
      const {},
      connectError: const AppException(ErrorCode.connHostUnreachable),
    );
    final container = await makeContainer(client);
    await notifier(container).start(password: 'pw');
    final state = read(container);
    expect(state, isA<SshShellError>());
    expect((state as SshShellError).code, ErrorCode.connHostUnreachable);
    // The connection must not leak on the error path.
    expect(client.closeCount, 1);
  });

  test('the remote ending the session yields a closed state', () async {
    final client = FakeSshClient(const {});
    final container = await makeContainer(client);
    await notifier(container).start(password: 'pw');
    client.shellSession.endRemote();
    await _settle();
    expect(read(container), isA<SshShellClosed>());
  });

  test('resize is forwarded to the live session', () async {
    final client = FakeSshClient(const {});
    final container = await makeContainer(client);
    await notifier(container).start(password: 'pw');
    notifier(container).resize(100, 40);
    expect(client.shellSession.resizes, [(columns: 100, rows: 40)]);
  });

  test('disposing the provider closes the session and connection', () async {
    final client = FakeSshClient(const {});
    final container = await makeContainer(client);
    await notifier(container).start(password: 'pw');
    container.dispose();
    await _settle();
    expect(client.shellSession.closed, isTrue);
    expect(client.closeCount, 1);
  });
}
