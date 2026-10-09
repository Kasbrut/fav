import 'package:fav/core/errors/app_exception.dart';
import 'package:fav/features/install/data/ssh/dart_ssh_client.dart';
import 'package:fav/features/install/data/ssh/host_key_store.dart';
import 'package:fav/features/install/domain/ssh_client.dart';
import 'package:fav/features/servers/application/server_list_controller.dart';
import 'package:fav/features/servers/data/hive_server_repository.dart';
import 'package:fav/features/servers/data/server_probe.dart';
import 'package:fav/features/servers/domain/host_key_fingerprint.dart';
import 'package:fav/features/servers/domain/server.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

/// State of the add-server connect → probe → save flow.
sealed class AddServerState {
  /// Const base constructor.
  const AddServerState();
}

/// The form is being filled; no operation is in progress.
class AddServerEditing extends AddServerState {
  /// Creates an [AddServerEditing] state.
  const AddServerEditing();
}

/// An SSH connection attempt is in progress.
class AddServerConnecting extends AddServerState {
  /// Creates an [AddServerConnecting] state.
  const AddServerConnecting();
}

/// The host key has never been pinned and awaits the user's confirmation.
class AddServerHostKeyPending extends AddServerState {
  /// Creates an [AddServerHostKeyPending] state for [fingerprint].
  const AddServerHostKeyPending(
    this.fingerprint, {
    this.previouslyTrusted = false,
  });

  /// The unverified host key fingerprint to show to the user.
  final HostKeyFingerprint fingerprint;

  /// True when this is a re-confirmation of a legacy (MD5-era) pin, not a
  /// first connection — the dialog copy differs (security audit M1).
  final bool previouslyTrusted;
}

/// The server is connected; the system probe is running.
class AddServerProbing extends AddServerState {
  /// Creates an [AddServerProbing] state.
  const AddServerProbing();
}

/// The server was added and saved successfully.
class AddServerSuccess extends AddServerState {
  /// Creates an [AddServerSuccess] state for the saved [server].
  const AddServerSuccess(this.server);

  /// The server that was added.
  final Server server;
}

/// The flow failed with [code].
class AddServerFailure extends AddServerState {
  /// Creates an [AddServerFailure] state.
  const AddServerFailure(this.code);

  /// The error code to surface to the user.
  final ErrorCode code;
}

/// Drives the add-server flow: connect, verify host key, probe, save.
///
/// The controller never stores the SSH password: it is passed into [submit]
/// per attempt and only ever a transient argument (spec RF-20, §10). On an
/// unknown host key the caller pins it via [confirmHostKey] and calls [submit]
/// again with the form values still held by the screen.
class AddServerController extends Notifier<AddServerState> {
  @override
  AddServerState build() => const AddServerEditing();

  /// Runs the connect → probe → save flow for the given form values.
  Future<void> submit({
    required String label,
    required SshConnectionParams params,
  }) async {
    state = const AddServerConnecting();
    final client = ref.read(sshClientFactoryProvider)();
    try {
      await client.connect(params);
      state = const AddServerProbing();
      final metadata = await ref.read(serverProbeProvider).probe(client);
      final pinnedKey = await ref
          .read(hostKeyStoreProvider)
          .lookup(params.host, params.port);
      // Reuse an existing record for the same endpoint instead of stacking a
      // duplicate — a retried failed install re-runs this flow with the same
      // host:port:user (audit M1). Hive `put` on the same id updates in place;
      // carry over the secrets/installation the record already holds.
      final existing = (await ref.read(serverRepositoryProvider).getAll())
          .where(
            (s) =>
                s.host == params.host &&
                s.sshPort == params.port &&
                s.username == params.username,
          )
          .firstOrNull;
      final now = DateTime.now();
      final server = Server(
        id: existing?.id ?? const Uuid().v4(),
        label: label,
        host: params.host,
        sshPort: params.port,
        username: params.username,
        metadata: metadata,
        pinnedHostKey: pinnedKey,
        createdAt: existing?.createdAt ?? now,
        lastSeenAt: now,
        sshKeyId: existing?.sshKeyId,
        installation: existing?.installation,
        userAuthorizedKeys: existing?.userAuthorizedKeys ?? const [],
      );
      await ref.read(serverRepositoryProvider).save(server);
      // Refresh the list so the newly added server appears immediately.
      ref.invalidate(serverListControllerProvider);
      state = AddServerSuccess(server);
    } on HostKeyUnknownException catch (error) {
      state = AddServerHostKeyPending(
        error.fingerprint,
        previouslyTrusted: error.previouslyTrusted,
      );
    } on AppException catch (error) {
      state = AddServerFailure(error.code);
    } on Object {
      state = const AddServerFailure(ErrorCode.connHostUnreachable);
    } finally {
      await client.close();
    }
  }

  /// Pins the pending host key, then returns to the editing state.
  ///
  /// The caller re-runs [submit] with the form values to retry the connection.
  Future<void> confirmHostKey() async {
    final current = state;
    if (current is! AddServerHostKeyPending) {
      return;
    }
    await ref.read(hostKeyStoreProvider).pin(current.fingerprint);
    state = const AddServerEditing();
  }

  /// Abandons a pending host key confirmation and returns to the form.
  void cancelHostKey() {
    state = const AddServerEditing();
  }
}

/// Controls the add-server connect/probe flow.
final NotifierProvider<AddServerController, AddServerState>
addServerControllerProvider =
    NotifierProvider.autoDispose<AddServerController, AddServerState>(
      AddServerController.new,
    );
