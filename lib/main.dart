import 'package:fav/app.dart';
import 'package:fav/core/persistence/app_database.dart';
import 'package:fav/core/persistence/secure_store.dart';
import 'package:fav/features/peers/data/hive_peer_repository.dart';
import 'package:fav/features/peers/data/legacy_peer_migrator.dart';
import 'package:fav/features/peers/data/secure_peer_secret_repository.dart';
import 'package:fav/features/servers/data/hive_server_repository.dart';
import 'package:fav/features/settings/application/preferences_controller.dart';
import 'package:fav/features/settings/data/preferences_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Application entry point.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final AppDatabase database;
  try {
    database = await bootstrapAppDatabase();
    final secureStore = createSecureStore();
    // Multi-peer v1.1: migrate any legacy `client_profile:<serverId>` entries
    // into the new peers box + `client_profile:<peerId>` layout. Idempotent —
    // re-running on a fully-migrated install is a no-op. We use a stable
    // English label "First client" so the persisted value does not depend on
    // the OS locale at upgrade time; users can rename peers in-app.
    final migrator = LegacyPeerMigrator(
      serverRepository: HiveServerRepository(database.serversBox),
      peerRepository: HivePeerRepository(database.peersBox),
      peerSecretRepository: SecurePeerSecretRepository(secureStore),
      secureStore: secureStore,
    );
    await migrator.migrate(firstClientLabel: 'First client');
  } on Object catch (error) {
    // A keystore-key/Hive mismatch (e.g. an OS backup restored onto another
    // device) used to die as a white screen with no way out (audit M10).
    runApp(BootFailureApp(error: error));
    return;
  }
  runApp(
    ProviderScope(
      // Riverpod 3 retries a failing provider automatically. This app models
      // failures as terminal states surfaced to the user (ERR-xx, spec §11)
      // with a user-driven retry, so silent auto-retry is disabled: it would
      // re-run SSH operations and could mask host-key/MITM errors.
      retry: (_, _) => null,
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        preferencesRepositoryProvider.overrideWithValue(
          PreferencesRepository(database.preferencesBox),
        ),
      ],
      child: const WireguardProvisionerApp(),
    ),
  );
}
