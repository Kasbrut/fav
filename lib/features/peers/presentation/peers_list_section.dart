import 'dart:async';

import 'package:fav/core/errors/app_exception.dart';
import 'package:fav/core/errors/error_messages.dart';
import 'package:fav/core/router/app_router.dart';
import 'package:fav/core/theme/app_dimens.dart';
import 'package:fav/core/widgets/app_card.dart';
import 'package:fav/core/widgets/primary_button.dart';
import 'package:fav/core/widgets/section_header.dart';
import 'package:fav/features/help/application/recent_errors_provider.dart';
import 'package:fav/features/help/presentation/error_help_link.dart';
import 'package:fav/features/install/domain/ssh_client.dart';
import 'package:fav/features/monitoring/application/monitor_polling_controller.dart';
import 'package:fav/features/monitoring/domain/peer_snapshot.dart';
import 'package:fav/features/peers/application/peers_controller.dart';
import 'package:fav/features/peers/domain/peer.dart';
import 'package:fav/features/peers/presentation/widgets/peer_list_tile.dart';
import 'package:fav/features/peers/presentation/widgets/peer_rename_dialog.dart';
import 'package:fav/features/peers/presentation/widgets/peer_revoke_confirm_dialog.dart';
import 'package:fav/features/servers/presentation/widgets/host_key_dialog.dart';
import 'package:fav/features/servers/presentation/widgets/password_prompt_dialog.dart';
import 'package:fav/features/settings/application/preferences_controller.dart';
import 'package:fav/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Recency window matching M15's `ClientLiveStatusBanner`.
const Duration _handshakeFreshWindow = Duration(minutes: 3);

/// The peers section embedded in `ServerDetailScreen`: list with live status,
/// rename + revoke overflow actions, and the "Add peer" CTA.
class PeersListSection extends ConsumerWidget {
  /// Creates a [PeersListSection] for the server identified by [serverId].
  const PeersListSection({required this.serverId, super.key});

  /// Identifier of the server whose peers are shown.
  final String serverId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final async = ref.watch(peersControllerProvider(serverId));
    final monitor = ref.watch(monitorPollingControllerProvider(serverId));
    final snapshot = monitor.snapshot;

    return Column(
      key: const Key('peers-section'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(label: l10n.peersSectionTitle),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          width: double.infinity,
          child: async.when(
            loading: () => const AppCard(
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (_, _) => AppCard(child: Text(l10n.errPeerParseFailed)),
            data: (peers) => AppCard(
              child: _PeerList(
                serverId: serverId,
                peers: peers,
                snapshot: snapshot,
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        PrimaryButton(
          label: l10n.actionAddPeer,
          icon: Icons.person_add_alt_1_outlined,
          onPressed: () => context.push(addPeerPath(serverId)),
        ),
      ],
    );
  }
}

class _PeerList extends ConsumerWidget {
  const _PeerList({
    required this.serverId,
    required this.peers,
    required this.snapshot,
  });

  final String serverId;
  final List<Peer> peers;
  final PeersStateSnapshot? snapshot;

  PeerLiveStatus _statusFor(Peer peer) {
    final snap = snapshot;
    if (snap == null) {
      return PeerLiveStatus.unknown;
    }
    final match = snap.peers.where((p) => p.publicKey == peer.publicKey);
    if (match.isEmpty) {
      return PeerLiveStatus.offline;
    }
    final entry = match.first;
    if (entry.latestHandshake <= 0) {
      return PeerLiveStatus.offline;
    }
    final handshakeAt = DateTime.fromMillisecondsSinceEpoch(
      entry.latestHandshake * 1000,
      isUtc: true,
    );
    final age = snap.generatedAt.toUtc().difference(handshakeAt);
    return age <= _handshakeFreshWindow
        ? PeerLiveStatus.online
        : PeerLiveStatus.offline;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    if (peers.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.lg,
        ),
        child: Text(
          l10n.peersEmptyHint,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }
    return Column(
      children: [
        for (final peer in peers)
          PeerListTile(
            peer: peer,
            status: _statusFor(peer),
            onTap: () => context.push(peerDetailPath(serverId, peer.id)),
            onRename: () => _onRename(context, ref, peer),
            onRevoke: () => _onRevoke(context, ref, peer),
          ),
      ],
    );
  }

  Future<void> _onRename(BuildContext context, WidgetRef ref, Peer peer) async {
    final newLabel = await showPeerRenameDialog(
      context: context,
      currentLabel: peer.label,
    );
    if (newLabel == null || !context.mounted) {
      return;
    }
    try {
      await ref
          .read(peersControllerProvider(serverId).notifier)
          .renamePeer(peer: peer, newLabel: newLabel);
    } on AppException catch (error) {
      if (context.mounted) {
        ref.read(recentErrorsProvider.notifier).record(error.code);
        unawaited(
          ref
              .read(preferencesControllerProvider.notifier)
              .recordError(error.code.id, DateTime.now()),
        );
        final l10n = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(localizedErrorMessage(l10n, error.code)),
            action: errorHelpSnackBarAction(context, ref, error.code),
          ),
        );
      }
    }
  }

  Future<void> _onRevoke(BuildContext context, WidgetRef ref, Peer peer) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showPeerRevokeConfirmDialog(context: context);
    if (!(confirmed ?? false) || !context.mounted) {
      return;
    }
    final password = await showPasswordPrompt(
      context,
      '${peer.label} — ${peer.address}',
    );
    if (password == null || password.isEmpty || !context.mounted) {
      return;
    }
    try {
      await ref
          .read(peersControllerProvider(serverId).notifier)
          .revokePeer(peer: peer, password: password);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.peerRevokedSnack(peer.label))),
        );
      }
    } on HostKeyUnknownException catch (pending) {
      // Confirm-pin-retry, like every interactive SSH entry point (M3).
      if (!context.mounted) return;
      if (await confirmPendingHostKey(context, ref, pending) &&
          context.mounted) {
        await _onRevoke(context, ref, peer);
      }
      return;
    } on AppException catch (error) {
      if (context.mounted) {
        ref.read(recentErrorsProvider.notifier).record(error.code);
        unawaited(
          ref
              .read(preferencesControllerProvider.notifier)
              .recordError(error.code.id, DateTime.now()),
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(localizedErrorMessage(l10n, error.code)),
            action: errorHelpSnackBarAction(context, ref, error.code),
          ),
        );
      }
    } on Object {
      if (context.mounted) {
        ref
            .read(recentErrorsProvider.notifier)
            .record(ErrorCode.connHostUnreachable);
        unawaited(
          ref
              .read(preferencesControllerProvider.notifier)
              .recordError(ErrorCode.connHostUnreachable.id, DateTime.now()),
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              localizedErrorMessage(l10n, ErrorCode.connHostUnreachable),
            ),
            action: errorHelpSnackBarAction(
              context,
              ref,
              ErrorCode.connHostUnreachable,
            ),
          ),
        );
      }
    }
  }
}
