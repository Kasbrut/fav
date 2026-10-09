import 'package:fav/core/persistence/secure_store.dart';
import 'package:fav/core/sharing/profile_share_service.dart';
import 'package:fav/core/theme/app_theme.dart';
import 'package:fav/features/monitoring/application/client_live_status_provider.dart';
import 'package:fav/features/monitoring/domain/client_live_status.dart';
import 'package:fav/features/profile/data/secure_client_profile_repository.dart';
import 'package:fav/features/profile/presentation/profile_result_screen.dart';
import 'package:fav/features/servers/data/hive_server_repository.dart';
import 'package:fav/features/servers/domain/wireguard_installation.dart';
import 'package:fav/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/in_memory_secure_store.dart';
import '../../../support/server_fakes.dart';

// 32-byte all-zero base64 key — accepted by the X25519 derivation in the
// async parser (M15-T3). The server/PSK strings are not decoded, so they can
// stay as opaque placeholders.
const String _validConf = '''
[Interface]
PrivateKey = AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=
Address = 10.13.13.2/32, 2606:4700:4700::2/128
DNS = 1.1.1.1, 1.0.0.1
MTU = 1420

[Peer]
PublicKey = AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=
PresharedKey = AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=
Endpoint = vpn.example.com:51820
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
''';

class _RecordingShareService implements ProfileShareService {
  String? lastCopied;
  String? lastSharedContent;
  String? lastSharedSubject;
  Rect? lastShareOrigin;
  String? lastSavedName;
  String? lastSavedContent;
  String? savedReturn = 'wireguard-srv-1.conf';
  Exception? saveError;
  Exception? shareError;

  @override
  Future<String?> saveProfile({
    required String suggestedName,
    required String content,
  }) async {
    lastSavedName = suggestedName;
    lastSavedContent = content;
    if (saveError != null) {
      throw saveError!;
    }
    return savedReturn;
  }

  @override
  Future<void> shareProfile({
    required String content,
    required Rect sharePositionOrigin,
    String? subject,
  }) async {
    lastShareOrigin = sharePositionOrigin;
    if (shareError != null) throw shareError!;
    lastSharedContent = content;
    lastSharedSubject = subject;
  }

  @override
  Future<void> copyProfile(String content) async {
    lastCopied = content;
  }
}

Future<void> _pumpScreen(
  WidgetTester tester, {
  required String serverId,
  required ProfileShareService share,
  String? seedRawConf,
  String serverLabel = 'vps-test',
  Ipv6Mode ipv6Mode = Ipv6Mode.routed,
}) async {
  // The screen is a single ListView whose Copy/Share/Save buttons sit below
  // the default 800x600 test viewport; ListView only materializes children
  // in the viewport, so the buttons would not exist in the element tree.
  // Grow the surface so the whole screen is rendered.
  await tester.binding.setSurfaceSize(const Size(800, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final store = InMemorySecureStore();
  if (seedRawConf != null) {
    await SecureClientProfileRepository(
      store,
    ).save(serverId: serverId, rawConf: seedRawConf);
  }
  final serverRepository = FakeServerRepository();
  final ipv6Subnet = ipv6Mode == Ipv6Mode.routed
      ? '2606:4700:4700::/64'
      : 'fd12:3456:789a::/64';
  await serverRepository.save(
    testServer(id: serverId, label: serverLabel).copyWith(
      installation: WireguardInstallation(
        interfaceName: 'wg0',
        listenPort: 51820,
        vpnSubnet: '10.13.13.0/24',
        serverPublicKey: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
        peers: const [],
        hardeningApplied: false,
        installedAt: DateTime.utc(2026, 9, 18),
        network: NetworkConfiguration(
          schemaVersion: 2,
          installationId: serverId,
          revision: 1,
          ipv6Mode: ipv6Mode,
          ipv4Subnet: '10.13.13.0/24',
          ipv6Subnet: ipv6Subnet,
          fallbackIpv6Subnet: 'fd12:3456:789a::/64',
          serverIpv6Address: ipv6Subnet.replaceFirst('::/64', '::1/64'),
          capabilityStatus: ipv6Mode == Ipv6Mode.routed
              ? CapabilityStatus.supported
              : CapabilityStatus.unknown,
          capabilityReason: ipv6Mode == Ipv6Mode.routed
              ? 'return_path_verified'
              : 'no_delegated_prefix',
          capabilityCheckedAt: DateTime.utc(2026, 9, 18),
          status: NetworkMetadataStatus.valid,
        ),
      ),
    ),
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        secureStoreProvider.overrideWithValue(store),
        serverRepositoryProvider.overrideWithValue(serverRepository),
        profileShareServiceProvider.overrideWithValue(share),
        // M15-T6: short-circuit the live-status provider so widget tests
        // do not spin up the SSH polling controller.
        clientLiveStatusProvider.overrideWith(
          (ref, key) => const ClientLiveStatusConnected(),
        ),
      ],
      child: MaterialApp(
        theme: lightTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ProfileResultScreen(serverId: serverId),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders QR, parsed details and the live status banner', (
    tester,
  ) async {
    final share = _RecordingShareService();
    await _pumpScreen(
      tester,
      serverId: 'srv-1',
      share: share,
      seedRawConf: _validConf,
    );

    // The banner is now driven by the monitoring provider — overridden
    // above to Connected, so the success text is rendered.
    expect(find.text('Connected'), findsOneWidget);
    expect(find.text('IPv6 routed through the VPN'), findsOneWidget);
    expect(find.text('Server configuration verified by FAV'), findsOneWidget);
    expect(
      find.text('Import on the destination client not verified'),
      findsOneWidget,
    );
    expect(find.text('vpn.example.com:51820'), findsOneWidget);
    expect(find.text('10.13.13.2/32'), findsOneWidget);
    expect(find.textContaining('0.0.0.0/0'), findsOneWidget);
    expect(find.textContaining('::/0'), findsOneWidget);
    expect(find.text('1420'), findsOneWidget);
    expect(find.text('25s'), findsOneWidget);
    // The raw .conf is hidden behind the "Show .conf" toggle by default.
    expect(find.text('Show .conf'), findsOneWidget);
    expect(find.textContaining('PrivateKey'), findsNothing);
  });

  testWidgets('shows blocked mode and keeps the client warning explicit', (
    tester,
  ) async {
    await _pumpScreen(
      tester,
      serverId: 'srv-1',
      share: _RecordingShareService(),
      seedRawConf: _validConf.replaceAll(
        '2606:4700:4700::',
        'fd12:3456:789a::',
      ),
      ipv6Mode: Ipv6Mode.blocked,
    );

    expect(find.text('IPv6 blocked inside the VPN'), findsOneWidget);
    expect(find.text('Client protection is not verified'), findsOneWidget);
  });

  testWidgets('Show .conf reveals the raw configuration', (tester) async {
    final share = _RecordingShareService();
    await _pumpScreen(
      tester,
      serverId: 'srv-1',
      share: share,
      seedRawConf: _validConf,
    );

    await tester.tap(find.text('Show .conf'));
    await tester.pumpAndSettle();

    expect(find.text('Hide .conf'), findsOneWidget);
    expect(
      find.textContaining(
        'PrivateKey = AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
      ),
      findsOneWidget,
    );
  });

  testWidgets('Copy calls the share service and shows a snackbar', (
    tester,
  ) async {
    final share = _RecordingShareService();
    await _pumpScreen(
      tester,
      serverId: 'srv-1',
      share: share,
      seedRawConf: _validConf,
    );

    await tester.tap(find.text('Copy'));
    await tester.pumpAndSettle();

    expect(share.lastCopied, _validConf);
    expect(
      find.text('Profile exported from FAV in this session'),
      findsOneWidget,
    );
    expect(find.textContaining('Profile copied to clipboard'), findsOneWidget);
    // The snackbar must warn the user that the clipboard now holds a secret
    // (security review M2 follow-up).
    expect(find.textContaining('private key'), findsOneWidget);
  });

  testWidgets('Share invokes the OS share sheet with the raw .conf', (
    tester,
  ) async {
    final share = _RecordingShareService();
    await _pumpScreen(
      tester,
      serverId: 'srv-1',
      share: share,
      seedRawConf: _validConf,
    );

    await tester.tap(find.text('Share'));
    await tester.pumpAndSettle();

    expect(share.lastSharedContent, _validConf);
    expect(share.lastSharedSubject, 'WireGuard client profile');
    expect(share.lastShareOrigin, isNotNull);
    expect(share.lastShareOrigin!.isEmpty, isFalse);
  });

  testWidgets('Save writes a WireGuard-valid .conf named after the server', (
    tester,
  ) async {
    final share = _RecordingShareService();
    await _pumpScreen(
      tester,
      serverId: 'srv-1',
      share: share,
      seedRawConf: _validConf,
      serverLabel: 'home-vpn',
    );

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(share.lastSavedName, 'home-vpn.conf');
    expect(share.lastSavedContent, _validConf);
  });

  testWidgets('shows the empty-state when no profile is saved', (tester) async {
    final share = _RecordingShareService();
    await _pumpScreen(tester, serverId: 'srv-1', share: share);

    expect(find.text('No client profile saved'), findsOneWidget);
    expect(find.text('Copy'), findsNothing);
  });
  testWidgets('Share failure is shown without exposing platform details', (
    tester,
  ) async {
    final share = _RecordingShareService()
      ..shareError = Exception('secret platform detail');
    await _pumpScreen(
      tester,
      serverId: 'srv-1',
      share: share,
      seedRawConf: _validConf,
    );
    await tester.tap(find.text('Share'));
    await tester.pumpAndSettle();
    expect(
      find.text('Could not export the profile. Try again.'),
      findsOneWidget,
    );
    expect(find.textContaining('secret platform detail'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
