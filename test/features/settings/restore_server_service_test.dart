import 'dart:convert';
import 'dart:typed_data';

import 'package:fav/core/crypto/ed25519_keypair.dart';
import 'package:fav/core/persistence/secure_store.dart';
import 'package:fav/features/install/data/keys/ssh_key_repository.dart';
import 'package:fav/features/install/data/ssh/dart_ssh_client.dart';
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
      expect(oldClient.runCommands, hasLength(2));
      expect(oldClient.runStdins.first, startsWith('ssh-ed25519 '));
      expect(
        oldClient.runStdins.last,
        oldPair.authorizedKeysEntry(comment: 'fav@server-1'),
      );
      expect(verificationClient.connectCount, 1);
    },
  );
}
