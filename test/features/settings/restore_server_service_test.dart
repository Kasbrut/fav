import 'dart:convert';
import 'dart:typed_data';

import 'package:fav/core/crypto/ed25519_keypair.dart';
import 'package:fav/core/persistence/secure_store.dart';
import 'package:fav/features/install/data/keys/ssh_key_repository.dart';
import 'package:fav/features/install/data/ssh/dart_ssh_client.dart';
import 'package:fav/features/install/domain/ssh_client.dart';
import 'package:fav/features/servers/domain/server.dart';
import 'package:fav/features/settings/application/restore_server_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_ssh_key_repository.dart';
import '../../support/in_memory_secure_store.dart';
import '../../support/recording_ssh_client.dart';

void main() {
  test('peer list parser accepts unique WireGuard keys', () {
    const first = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=';
    const second = 'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=';

    expect(parseWireGuardPeerKeys('$first\n$second\n$first'), {first, second});
  });

  test('peer list parser rejects unexpected server output', () {
    expect(
      () => parseWireGuardPeerKeys('permission denied'),
      throwsStateError,
    );
  });

  test(
    'rotation verifies and persists the new key before removing the old',
    () async {
      final oldPair = await Ed25519KeyPair.fromSeed(
        Uint8List.fromList(List<int>.generate(32, (index) => index)),
      );
      final store = InMemorySecureStore();
      await store.write('ssh-key:server-1', base64Encode(oldPair.seedBytes));
      final oldClient = RecordingSshClient();
      final verificationClient = RecordingSshClient();
      final clients = [oldClient, verificationClient];
      final container = ProviderContainer(
        overrides: [
          secureStoreProvider.overrideWithValue(store),
          sshKeyRepositoryProvider.overrideWithValue(
            FakeSshKeyRepository(oldPair),
          ),
          sshClientFactoryProvider.overrideWithValue(() => clients.removeAt(0)),
        ],
      );
      addTearDown(container.dispose);
      final server = Server(
        id: 'server-1',
        label: 'Server',
        host: 'vpn.example.com',
        sshPort: 22,
        username: 'admin',
        sshKeyId: 'server-1',
        createdAt: DateTime.utc(2026, 10, 8),
      );

      await container
          .read(restoreServerServiceProvider)
          .rotateFavourKey(server);

      final replacement = await store.read('ssh-key:server-1');
      expect(replacement, isNot(base64Encode(oldPair.seedBytes)));
      expect(oldClient.runCommands, hasLength(1));
      expect(oldClient.runStdins.first, startsWith('ssh-ed25519 '));
      expect(
        verificationClient.runStdins.first,
        oldPair.authorizedKeysEntry(comment: 'fav@server-1'),
      );
      expect(verificationClient.connectCount, 1);
      expect(verificationClient.runCommands, hasLength(2));
      expect(await store.read('ssh-rotation-pending:server-1'), isNull);
    },
  );

  for (final failure in [
    'journal write',
    'before seed commit',
    'after seed commit',
    'replacement authentication',
    'revocation',
    'revocation verification',
    'ineffective revocation',
    'journal deletion',
  ]) {
    test(
      'rotation recovers after $failure without losing either key',
      () async {
        final oldPair = await Ed25519KeyPair.fromSeed(
          Uint8List.fromList(List<int>.generate(32, (index) => index)),
        );
        final oldSeed = base64Encode(oldPair.seedBytes);
        final oldLine = oldPair.authorizedKeysEntry(comment: 'fav@server-1');
        final store = _FailingRotationStore();
        await store.write('ssh-key:server-1', oldSeed);
        store.failure = failure;
        final installed = <String>{oldLine};
        final clients = <RecordingSshClient>[];
        var injectRemoteFailure = true;
        RecordingSshClient clientFactory() {
          late RecordingSshClient client;
          client = RecordingSshClient(
            onConnect: () {
              if (clients.length == 2 &&
                  injectRemoteFailure &&
                  failure == 'replacement authentication') {
                injectRemoteFailure = false;
                throw StateError('injected authentication failure');
              }
            },
            onRun: (command) async {
              final line = client.runStdins.last!;
              if (command.contains('mkdir -p')) {
                // The journal must already exist before the server is changed.
                expect(
                  await store.read('ssh-rotation-pending:server-1'),
                  isNotNull,
                );
                installed.add(line);
              } else {
                // Revocation must never precede durable replacement storage.
                expect(await store.read('ssh-key:server-1'), isNot(oldSeed));
                final verification = command.contains(r'status=$?');
                if (injectRemoteFailure &&
                    failure ==
                        (verification
                            ? 'revocation verification'
                            : 'revocation')) {
                  injectRemoteFailure = false;
                  throw StateError('injected remote failure');
                }
                if (verification) {
                  return SshCommandResult(
                    stdout: '',
                    stderr: '',
                    exitCode: installed.contains(line) ? 1 : 0,
                  );
                }
                if (failure == 'ineffective revocation' &&
                    injectRemoteFailure) {
                  injectRemoteFailure = false;
                } else {
                  installed.remove(line);
                }
              }
              return const SshCommandResult(
                stdout: '',
                stderr: '',
                exitCode: 0,
              );
            },
          );
          clients.add(client);
          return client;
        }

        final container = ProviderContainer(
          overrides: [
            secureStoreProvider.overrideWithValue(store),
            sshClientFactoryProvider.overrideWithValue(clientFactory),
          ],
        );
        addTearDown(container.dispose);
        final server = _rotationServer();
        final service = container.read(restoreServerServiceProvider);

        await expectLater(service.rotateFavourKey(server), throwsStateError);
        final pending = await store.read('ssh-rotation-pending:server-1');
        if (failure == 'journal write') {
          expect(clients, isEmpty);
          expect(installed, {oldLine});
        } else {
          expect(pending, isNotNull);
        }
        if (failure == 'before seed commit' ||
            failure == 'replacement authentication') {
          expect(await store.read('ssh-key:server-1'), oldSeed);
          expect(installed, contains(oldLine));
        }
        final expectedSeed = pending == null
            ? null
            : (jsonDecode(pending) as Map<String, dynamic>)['newSeed'];
        store.failure = null;
        await service.rotateFavourKey(server);

        final replacementSeed = await store.read('ssh-key:server-1');
        if (expectedSeed != null) expect(replacementSeed, expectedSeed);
        final replacement = await Ed25519KeyPair.fromSeed(
          Uint8List.fromList(base64Decode(replacementSeed!)),
        );
        expect(installed, {
          replacement.authorizedKeysEntry(comment: 'fav@server-1'),
        });
        expect(await store.read('ssh-rotation-pending:server-1'), isNull);
        expect(clients.every((client) => client.closeCount == 1), isTrue);
      },
    );
  }

  test(
    'legacy pending revocation resumes with the committed replacement',
    () async {
      final pair = await Ed25519KeyPair.generate();
      final oldPair = await Ed25519KeyPair.generate();
      final oldLine = oldPair.authorizedKeysEntry(comment: 'fav@server-1');
      final store = InMemorySecureStore();
      await store.write('ssh-key:server-1', base64Encode(pair.seedBytes));
      await store.write('ssh-rotation-pending:server-1', oldLine);
      final client = RecordingSshClient();
      final container = ProviderContainer(
        overrides: [
          secureStoreProvider.overrideWithValue(store),
          sshClientFactoryProvider.overrideWithValue(() => client),
        ],
      );
      addTearDown(container.dispose);
      await container
          .read(restoreServerServiceProvider)
          .rotateFavourKey(_rotationServer());
      expect(client.runStdins, [oldLine, oldLine]);
      expect(await store.read('ssh-rotation-pending:server-1'), isNull);
      expect(
        await store.read('ssh-key:server-1'),
        base64Encode(pair.seedBytes),
      );
    },
  );

  test(
    'legacy pending revocation cannot delete the only stored identity',
    () async {
      final pair = await Ed25519KeyPair.generate();
      final store = InMemorySecureStore();
      await store.write('ssh-key:server-1', base64Encode(pair.seedBytes));
      await store.write(
        'ssh-rotation-pending:server-1',
        pair.authorizedKeysEntry(comment: 'fav@server-1'),
      );
      final container = ProviderContainer(
        overrides: [
          secureStoreProvider.overrideWithValue(store),
          sshClientFactoryProvider.overrideWithValue(
            () => throw StateError('unexpected SSH'),
          ),
        ],
      );
      addTearDown(container.dispose);
      await expectLater(
        container
            .read(restoreServerServiceProvider)
            .rotateFavourKey(_rotationServer()),
        throwsStateError,
      );
      expect(await store.read('ssh-rotation-pending:server-1'), isNotNull);
      expect(
        await store.read('ssh-key:server-1'),
        base64Encode(pair.seedBytes),
      );
    },
  );
}

Server _rotationServer() => Server(
  id: 'server-1',
  label: 'Server',
  host: 'vpn.example.com',
  sshPort: 22,
  username: 'admin',
  sshKeyId: 'server-1',
  createdAt: DateTime.utc(2026, 10, 8),
);

class _FailingRotationStore extends InMemorySecureStore {
  String? failure;

  @override
  Future<void> write(String key, String value) async {
    if ((failure == 'journal write' &&
            key.startsWith('ssh-rotation-pending:')) ||
        (failure == 'before seed commit' && key.startsWith('ssh-key:'))) {
      throw StateError('injected storage failure');
    }
    await super.write(key, value);
    if (failure == 'after seed commit' && key.startsWith('ssh-key:')) {
      throw StateError('injected failure after durable seed write');
    }
  }

  @override
  Future<void> delete(String key) async {
    if (failure == 'journal deletion') {
      throw StateError('injected deletion failure');
    }
    await super.delete(key);
  }
}
