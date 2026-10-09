import 'package:fav/core/errors/app_exception.dart';
import 'package:fav/core/utils/app_logger.dart';
import 'package:fav/features/install/application/reopen_ssh_service.dart';
import 'package:fav/features/install/application/services_teardown_service.dart';
import 'package:fav/features/install/application/ssh_auth_resolver.dart';
import 'package:fav/features/install/data/keys/ssh_key_repository.dart';
import 'package:fav/features/install/data/scripts/asset_script_repository.dart';
import 'package:fav/features/install/data/scripts/script_integrity.dart';
import 'package:fav/features/install/data/ssh/dart_ssh_client.dart';
import 'package:fav/features/install/domain/run_paths.dart';
import 'package:fav/features/servers/application/app_key_removal.dart';
import 'package:fav/features/servers/application/server_list_controller.dart';
import 'package:fav/features/servers/application/teardown_guard.dart';
import 'package:fav/features/servers/domain/server.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';

/// Immutable inputs describing a requested teardown.
@immutable
class TeardownRequest {
  /// Creates a [TeardownRequest].
  const TeardownRequest({
    required this.server,
    required this.removeServices,
    required this.reopenSsh,
  });

  /// The server to tear down.
  final Server server;

  /// Whether to run the services teardown on the server.
  final bool removeServices;

  /// Whether to re-open SSH (reverse hardening) before removing the app key.
  final bool reopenSsh;
}

/// State machine for [ServerTeardownController].
@immutable
sealed class TeardownFlowState {
  const TeardownFlowState();
}

/// Nothing has happened yet.
class TeardownIdle extends TeardownFlowState {
  /// Creates a [TeardownIdle].
  const TeardownIdle();
}

/// Refused before connecting: would strip the last SSH access path.
class TeardownLockoutRisk extends TeardownFlowState {
  /// Creates a [TeardownLockoutRisk].
  const TeardownLockoutRisk();
}

/// Re-opening SSH (reversing the hardening) over the open connection.
class TeardownReopeningSsh extends TeardownFlowState {
  /// Creates a [TeardownReopeningSsh].
  const TeardownReopeningSsh();
}

/// The synchronous services teardown is running over the open connection.
class TeardownRunningServices extends TeardownFlowState {
  /// Creates a [TeardownRunningServices].
  const TeardownRunningServices();
}

/// Removing FAV's deployed app key — the key we are connected with — last.
class TeardownRemovingAppKey extends TeardownFlowState {
  /// Creates a [TeardownRemovingAppKey].
  const TeardownRemovingAppKey();
}

/// The teardown finished and the local record was removed.
class TeardownDone extends TeardownFlowState {
  /// Creates a [TeardownDone].
  const TeardownDone();
}

/// Remote teardown failed; the local record is untouched. The UI offers
/// retry or remove-locally-anyway.
class TeardownFailure extends TeardownFlowState {
  /// Creates a [TeardownFailure] carrying [error].
  const TeardownFailure(this.error);

  /// The failure to surface to the user.
  final AppException error;
}

/// Orchestrates the optional remote teardown then the local removal.
///
/// Order is load-bearing: resolve auth, open ONE connection, then re-open SSH
/// (sync), services teardown (sync, staged in /tmp and run via sudo), and
/// finally remove the app key — the very key the connection authenticates with
/// — before closing and removing the local record. The local cleanup runs only
/// after the remote steps succeed (or when none were requested).
class ServerTeardownController extends Notifier<TeardownFlowState> {
  TeardownRequest? _last;

  @override
  TeardownFlowState build() => const TeardownIdle();

  /// Runs the requested teardown. Refuses ([TeardownLockoutRisk]) when the
  /// guard trips and the user did not opt to re-open SSH.
  Future<void> teardown({
    required Server server,
    required bool removeServices,
    required bool reopenSsh,
    required String password,
  }) async {
    final request = TeardownRequest(
      server: server,
      removeServices: removeServices,
      reopenSsh: reopenSsh,
    );
    _last = request;

    if (teardownWouldLockOut(server: server, reopenSsh: reopenSsh)) {
      state = const TeardownLockoutRisk();
      return;
    }

    final client = ref.read(sshClientFactoryProvider)();
    try {
      final params = await ref
          .read(sshAuthResolverProvider)
          .resolve(server: server, password: password);
      await client.connect(params);

      // The teardown runs as root; sudo is required when not connected as
      // root (post-hardening login is the non-root sudoer).
      final sudoPassword = server.username == 'root' ? null : password;

      if (reopenSsh) {
        state = const TeardownReopeningSsh();
        final bundle = await ref.read(bootIntegrityProvider.future);
        final scriptBytes = bundle.assets
            .firstWhere((a) => a.relativePath == kReopenSshScript)
            .bytes;
        final outcome = await ref
            .read(reopenSshServiceProvider)
            .reopen(
              client: client,
              paths: RunPaths.generate(),
              scriptBytes: scriptBytes,
              sudoPassword: password,
            );
        if (outcome is ReopenSshAborted) {
          state = TeardownFailure(outcome.error);
          return;
        }
      }

      if (removeServices) {
        state = const TeardownRunningServices();
        final bundle = await ref.read(bootIntegrityProvider.future);
        final outcome = await ref
            .read(servicesTeardownServiceProvider)
            .run(
              client: client,
              bundle: bundle,
              interfaceName: server.installation?.interfaceName ?? 'wg0',
              vpnSubnet: server.installation?.vpnSubnet ?? '10.13.13.0/24',
              sudoPassword: sudoPassword,
            );
        if (outcome is ServicesTeardownAborted) {
          state = TeardownFailure(outcome.error);
          return;
        }
      }

      // Remove the app key LAST — it is the key we are connected with.
      final keyId = server.sshKeyId;
      if (keyId != null) {
        state = const TeardownRemovingAppKey();
        final keyPair = await ref.read(sshKeyRepositoryProvider).get(keyId);
        if (keyPair != null) {
          await removeAppKeyFromAuthorizedKeys(
            client: client,
            publicKeyLine: keyPair.authorizedKeysEntry(
              comment: 'fav@${server.id}',
            ),
          );
        }
      }
    } on AppException catch (error) {
      state = TeardownFailure(error);
      return;
    } on Object catch (error, stack) {
      appLogger.w('Teardown failed: ${error.runtimeType}\n$stack');
      state = const TeardownFailure(
        AppException(ErrorCode.connHostUnreachable),
      );
      return;
    } finally {
      await client.close();
    }

    // Remote steps succeeded (or none were requested) → local cleanup.
    await ref.read(serverListControllerProvider.notifier).delete(server.id);
    _last = null;
    state = const TeardownDone();
  }

  /// Re-runs the last requested teardown (scripts are idempotent).
  Future<void> retry({required String password}) async {
    final last = _last;
    if (last == null) return;
    await teardown(
      server: last.server,
      removeServices: last.removeServices,
      reopenSsh: last.reopenSsh,
      password: password,
    );
  }

  /// Skips the remote teardown and removes only the local record.
  Future<void> removeLocallyAnyway() async {
    final last = _last;
    if (last == null) return;
    await ref
        .read(serverListControllerProvider.notifier)
        .delete(last.server.id);
    _last = null;
    state = const TeardownDone();
  }

  /// Removes the local record immediately without opening an SSH connection.
  Future<void> removeLocally(Server server) async {
    await ref.read(serverListControllerProvider.notifier).delete(server.id);
    _last = null;
    state = const TeardownDone();
  }
}

/// Provides the [ServerTeardownController].
final NotifierProvider<ServerTeardownController, TeardownFlowState>
serverTeardownControllerProvider =
    NotifierProvider<ServerTeardownController, TeardownFlowState>(
      ServerTeardownController.new,
    );
