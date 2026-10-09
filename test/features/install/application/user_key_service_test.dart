// The SSH key fixture is a single unsplittable base64 token.
// ignore_for_file: lines_longer_than_80_chars

import 'package:fav/core/crypto/ed25519_keypair.dart';
import 'package:fav/core/errors/app_exception.dart';
import 'package:fav/features/install/application/user_key_service.dart';
import 'package:fav/features/install/data/keys/ssh_key_repository.dart';
import 'package:fav/features/install/data/ssh/dart_ssh_client.dart';
import 'package:fav/features/install/domain/ssh_client.dart';
import 'package:fav/features/servers/data/hive_server_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/recording_ssh_client.dart';
import '../../../support/server_fakes.dart';

const _key1 =
    'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILumuaB4RSmE61UE6zVVVutcGA5HoayYq1PhFhdkFg9e user@laptop';
const _key2 = 'ssh-rsa AAAAB3NzaC1yc2E= desktop';

/// [SshKeyRepository] returning a fixed key for a single server id.
class _FakeSshKeyRepository implements SshKeyRepository {
  _FakeSshKeyRepository(this._keyId, this._pair);

  final String _keyId;
  final Ed25519KeyPair _pair;

  @override
  Future<Ed25519KeyPair?> get(String serverId) async =>
      serverId == _keyId ? _pair : null;

  @override
  Future<Ed25519KeyPair> getOrCreate({
    required String serverId,
    required String comment,
  }) async => _pair;

  @override
  Future<void> delete(String serverId) async {}
}

ProviderContainer _container({
  required RecordingSshClient ssh,
  required FakeServerRepository repo,
  SshKeyRepository? keyRepo,
}) {
  final container = ProviderContainer(
    overrides: [
      sshClientFactoryProvider.overrideWithValue(() => ssh),
      serverRepositoryProvider.overrideWithValue(repo),
      if (keyRepo != null) sshKeyRepositoryProvider.overrideWithValue(keyRepo),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('UserKeyService.addKeys', () {
    test(
      'deploys each fresh key via stdin and records them on the server',
      () async {
        final ssh = RecordingSshClient();
        final repo = FakeServerRepository();
        final server = testServer();
        await repo.save(server);
        final service = _container(ssh: ssh, repo: repo).read(
          userKeyServiceProvider,
        );

        final updated = await service.addKeys(
          server: server,
          keyLines: const [_key1, _key2],
          password: 'pw',
        );

        // Each key is fed through stdin, never interpolated into the command.
        expect(ssh.runStdins, [_key1, _key2]);
        expect(ssh.runCommands.every((c) => !c.contains(_key1)), isTrue);
        expect(updated.userAuthorizedKeys, [_key1, _key2]);
        // Persisted.
        expect((await repo.getById(server.id))!.userAuthorizedKeys, [
          _key1,
          _key2,
        ]);
        expect(ssh.closeCount, 1);
      },
    );

    test(
      'skips keys already present and does not reconnect when none new',
      () async {
        final ssh = RecordingSshClient();
        final repo = FakeServerRepository();
        final server = testServer().copyWith(userAuthorizedKeys: const [_key1]);
        await repo.save(server);
        final service = _container(ssh: ssh, repo: repo).read(
          userKeyServiceProvider,
        );

        final updated = await service.addKeys(
          server: server,
          keyLines: const [_key1],
          password: 'pw',
        );

        expect(ssh.connectCount, 0);
        expect(updated.userAuthorizedKeys, [_key1]);
      },
    );

    test('throws and closes when the remote command fails', () async {
      final ssh = RecordingSshClient(
        onRun: (_) =>
            const SshCommandResult(stdout: '', stderr: 'boom', exitCode: 1),
      );
      final repo = FakeServerRepository();
      final server = testServer();
      await repo.save(server);
      final service = _container(ssh: ssh, repo: repo).read(
        userKeyServiceProvider,
      );

      await expectLater(
        service.addKeys(
          server: server,
          keyLines: const [_key1],
          password: 'pw',
        ),
        throwsA(
          isA<AppException>().having(
            (e) => e.code,
            'code',
            ErrorCode.sshKeyDeployFailed,
          ),
        ),
      );
      expect(ssh.closeCount, 1);
      // Nothing was persisted.
      expect((await repo.getById(server.id))!.userAuthorizedKeys, isEmpty);
    });

    test('skips invalid lines without connecting', () async {
      final ssh = RecordingSshClient();
      final repo = FakeServerRepository();
      final server = testServer();
      await repo.save(server);
      final service = _container(ssh: ssh, repo: repo).read(
        userKeyServiceProvider,
      );

      final updated = await service.addKeys(
        server: server,
        keyLines: const ['not a valid key'],
        password: 'pw',
      );

      expect(ssh.connectCount, 0);
      expect(updated.userAuthorizedKeys, isEmpty);
    });

    test('excludes the app key to preserve anti-lockout', () async {
      final appPair = await Ed25519KeyPair.generate();
      final appLine = appPair.authorizedKeysEntry(comment: 'fav@srv-1');
      final ssh = RecordingSshClient();
      final repo = FakeServerRepository();
      // testServer() has id 'srv-1'; mark it key-managed.
      final server = testServer().copyWith(sshKeyId: 'srv-1');
      await repo.save(server);
      final service = _container(
        ssh: ssh,
        repo: repo,
        keyRepo: _FakeSshKeyRepository('srv-1', appPair),
      ).read(userKeyServiceProvider);

      final updated = await service.addKeys(
        server: server,
        keyLines: [appLine],
        password: 'pw',
      );

      // The app key is rejected: no SSH session, nothing recorded.
      expect(ssh.connectCount, 0);
      expect(updated.userAuthorizedKeys, isEmpty);
    });
  });

  group('UserKeyService.removeKey', () {
    test('does nothing for an untracked key', () async {
      final ssh = RecordingSshClient();
      final repo = FakeServerRepository();
      final server = testServer();
      await repo.save(server);
      final service = _container(ssh: ssh, repo: repo).read(
        userKeyServiceProvider,
      );

      final updated = await service.removeKey(
        server: server,
        keyLine: _key1,
        password: 'pw',
      );

      expect(ssh.connectCount, 0);
      expect(updated.userAuthorizedKeys, isEmpty);
    });

    test('removes the exact line and updates the server', () async {
      final ssh = RecordingSshClient();
      final repo = FakeServerRepository();
      final server = testServer().copyWith(
        userAuthorizedKeys: const [_key1, _key2],
      );
      await repo.save(server);
      final service = _container(ssh: ssh, repo: repo).read(
        userKeyServiceProvider,
      );

      final updated = await service.removeKey(
        server: server,
        keyLine: _key1,
        password: 'pw',
      );

      expect(ssh.runStdins, [_key1]);
      expect(updated.userAuthorizedKeys, [_key2]);
      expect((await repo.getById(server.id))!.userAuthorizedKeys, [_key2]);
    });
  });
}
