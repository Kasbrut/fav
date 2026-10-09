import 'package:fav/app.dart';
import 'package:fav/core/crypto/ed25519_keypair.dart';
import 'package:fav/core/persistence/secure_store.dart';
import 'package:fav/core/router/app_router.dart';
import 'package:fav/core/theme/app_theme.dart';
import 'package:fav/features/install/data/keys/ssh_key_repository.dart';
import 'package:fav/features/install/data/ssh/dart_ssh_client.dart';
import 'package:fav/features/install/data/ssh/host_key_store.dart';
import 'package:fav/features/peers/data/hive_peer_repository.dart';
import 'package:fav/features/peers/domain/peer.dart';
import 'package:fav/features/servers/data/hive_server_repository.dart';
import 'package:fav/features/servers/domain/wireguard_installation.dart';
import 'package:fav/features/servers/presentation/server_detail_screen.dart';
import 'package:fav/features/settings/application/preferences_controller.dart';
import 'package:fav/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_preferences_repository.dart';
import '../../../support/fake_ssh_key_repository.dart';
import '../../../support/in_memory_secure_store.dart';
import '../../../support/recording_ssh_client.dart';
import '../../../support/server_fakes.dart';
import '../../../support/static_peer_repository.dart';

void main() {
  testWidgets('the WireGuard card counts the actual peers', (tester) async {
    // `WireguardInstallation.peers` is written once (empty) at finalize and
    // never maintained afterwards: the card said "Peers: 0" while the peers
    // section right below listed the first client (device test 2026-08-19).
    // The count must come from the peer repository.
    final server = hardenedServerWithAppKey();
    final servers = FakeServerRepository();
    await servers.save(server);
    final peers = StaticPeerRepository([
      Peer(
        id: 'p1',
        serverId: server.id,
        label: 'First client',
        address: '10.13.13.2/32',
        publicKey: 'PUB',
        createdAt: DateTime(2026, 8, 19),
      ),
    ]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          secureStoreProvider.overrideWithValue(InMemorySecureStore()),
          serverRepositoryProvider.overrideWithValue(servers),
          peerRepositoryProvider.overrideWithValue(peers),
          sshClientFactoryProvider.overrideWithValue(RecordingSshClient.new),
          sshKeyRepositoryProvider.overrideWithValue(
            FakeSshKeyRepository(await Ed25519KeyPair.generate()),
          ),
        ],
        child: MaterialApp(
          theme: lightTheme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ServerDetailScreen(serverId: server.id),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    final peersRow = find.ancestor(
      of: find.text(l10n.detailWgPeers),
      matching: find.byType(Row),
    );
    expect(
      find.descendant(of: peersRow, matching: find.text('1')),
      findsOneWidget,
      reason: 'the card must count the stored peers, not the stale record',
    );
  });

  testWidgets('a blocked WireGuard port shows actionable firewall help', (
    tester,
  ) async {
    final base = hardenedServerWithAppKey();
    final server = base.copyWith(
      installation: base.installation!.copyWith(
        portReachability: WireguardPortReachability.blocked,
      ),
    );
    final servers = FakeServerRepository();
    await servers.save(server);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          secureStoreProvider.overrideWithValue(InMemorySecureStore()),
          serverRepositoryProvider.overrideWithValue(servers),
          peerRepositoryProvider.overrideWithValue(StaticPeerRepository([])),
          sshClientFactoryProvider.overrideWithValue(RecordingSshClient.new),
          sshKeyRepositoryProvider.overrideWithValue(
            FakeSshKeyRepository(await Ed25519KeyPair.generate()),
          ),
        ],
        child: MaterialApp(
          theme: lightTheme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ServerDetailScreen(serverId: server.id),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    expect(find.text(l10n.wireguardPortBlockedTitle), findsOneWidget);
    expect(find.text(l10n.actionOpenFirewallGuide), findsOneWidget);
  });

  testWidgets('firewall help opens from server detail inside the app shell', (
    tester,
  ) async {
    final base = hardenedServerWithAppKey();
    final server = base.copyWith(
      installation: base.installation!.copyWith(
        portReachability: WireguardPortReachability.blocked,
      ),
    );
    final servers = FakeServerRepository();
    await servers.save(server);
    final secureStore = InMemorySecureStore();
    final container = ProviderContainer(
      overrides: [
        secureStoreProvider.overrideWithValue(secureStore),
        hostKeyStoreProvider.overrideWithValue(HostKeyStore(secureStore)),
        serverRepositoryProvider.overrideWithValue(servers),
        peerRepositoryProvider.overrideWithValue(StaticPeerRepository([])),
        sshClientFactoryProvider.overrideWithValue(RecordingSshClient.new),
        sshKeyRepositoryProvider.overrideWithValue(
          FakeSshKeyRepository(await Ed25519KeyPair.generate()),
        ),
        preferencesRepositoryProvider.overrideWithValue(
          FakePreferencesRepository(),
        ),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const WireguardProvisionerApp(),
      ),
    );
    container.read(routerProvider).go(serverDetailPath(server.id));
    await tester.pumpAndSettle();

    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await tester.tap(find.text(l10n.actionOpenFirewallGuide));
    await tester.pumpAndSettle();

    expect(find.text(l10n.helpFirewallTitle), findsWidgets);
    expect(find.byType(NavigationRail), findsOneWidget);
    container.dispose();
    await tester.pump();
  });
}
