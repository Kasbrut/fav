import 'dart:async';

import 'package:fav/core/errors/app_exception.dart';
import 'package:fav/core/errors/error_messages.dart';
import 'package:fav/core/router/app_router.dart';
import 'package:fav/core/sharing/profile_share_service.dart';
import 'package:fav/core/theme/app_dimens.dart';
import 'package:fav/core/utils/wireguard_tunnel_name.dart';
import 'package:fav/core/widgets/empty_state.dart';
import 'package:fav/core/widgets/responsive_content.dart';
import 'package:fav/features/help/application/recent_errors_provider.dart';
import 'package:fav/features/help/presentation/error_help_link.dart';
import 'package:fav/features/peers/application/peer_secret_provider.dart';
import 'package:fav/features/peers/application/peers_controller.dart';
import 'package:fav/features/peers/domain/peer.dart';
import 'package:fav/features/peers/presentation/widgets/peer_rename_dialog.dart';
import 'package:fav/features/profile/presentation/profile_result_screen.dart';
import 'package:fav/features/servers/application/server_list_controller.dart';
import 'package:fav/features/settings/application/preferences_controller.dart';
import 'package:fav/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Per-peer detail screen for the multi-peer v1.1 flow: QR, parsed details,
/// the raw `.conf`, Share/Copy/Save actions, and an inline rename for the
/// peer label.
class PeerDetailScreen extends ConsumerStatefulWidget {
  /// Creates a [PeerDetailScreen].
  const PeerDetailScreen({
    required this.serverId,
    required this.peerId,
    super.key,
  });

  /// Server this peer belongs to (drives the M15 live banner).
  final String serverId;

  /// Identifier of the peer to display.
  final String peerId;

  @override
  ConsumerState<PeerDetailScreen> createState() => _PeerDetailScreenState();
}

class _PeerDetailScreenState extends ConsumerState<PeerDetailScreen> {
  bool _confExpanded = false;
  bool _profileExported = false;
  bool _clientImportDeclared = false;

  Future<void> _copy(String content) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(profileShareServiceProvider).copyProfile(content);
    } on Object {
      if (mounted) _showExportError();
      return;
    }
    if (!mounted) {
      return;
    }
    messenger.showSnackBar(SnackBar(content: Text(l10n.profileCopied)));
    setState(() => _profileExported = true);
  }

  void _showExportError() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context)!.profileExportFailed),
      ),
    );
  }

  Rect _shareOrigin() {
    final box = context.findRenderObject()! as RenderBox;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  Future<void> _share(String content) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      await ref
          .read(profileShareServiceProvider)
          .shareProfile(
            content: content,
            subject: l10n.profileShareSubject,
            sharePositionOrigin: _shareOrigin(),
          );
      if (mounted) setState(() => _profileExported = true);
    } on Object {
      if (mounted) _showExportError();
    }
  }

  Future<void> _save(String content, Peer? peer) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    // The WireGuard apps use the file name as the tunnel name and reject
    // anything over 15 chars or outside their charset, so derive a valid name
    // from the server/peer labels rather than the (too long) peer UUID.
    final servers = await ref.read(serverListControllerProvider.future);
    final serverLabel =
        servers.where((s) => s.id == widget.serverId).firstOrNull?.label ?? '';
    if (!mounted) {
      return;
    }
    try {
      final saved = await ref
          .read(profileShareServiceProvider)
          .saveProfile(
            suggestedName: wireguardConfFileName(
              serverLabel: serverLabel,
              peerLabel: peer?.label,
            ),
            content: content,
          );
      if (!mounted || saved == null) {
        return;
      }
      messenger.showSnackBar(SnackBar(content: Text(l10n.profileSaved)));
      setState(() => _profileExported = true);
    } on Object {
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(SnackBar(content: Text(l10n.profileExportFailed)));
    }
  }

  Future<void> _rename(Peer peer) async {
    final l10n = AppLocalizations.of(context)!;
    final newLabel = await showPeerRenameDialog(
      context: context,
      currentLabel: peer.label,
    );
    if (newLabel == null || !mounted) {
      return;
    }
    try {
      await ref
          .read(peersControllerProvider(widget.serverId).notifier)
          .renamePeer(peer: peer, newLabel: newLabel);
    } on AppException catch (error) {
      if (mounted) {
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
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final async = ref.watch(peerProfileProvider(widget.peerId));
    // The peer's label is mutable (rename), so source it from the controller
    // that the rename mutation writes to. Fall back to the FutureProvider's
    // copy on the first frame, before the controller list has resolved.
    final livePeer = ref
        .watch(peersControllerProvider(widget.serverId))
        .value
        ?.where((p) => p.id == widget.peerId)
        .firstOrNull;
    final bundle = async.value;
    final peer = livePeer ?? bundle?.peer;
    final server = ref
        .watch(serverListControllerProvider)
        .value
        ?.where((server) => server.id == widget.serverId)
        .firstOrNull;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const BackButtonIcon(),
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go(serverDetailPath(widget.serverId));
            }
          },
        ),
        title: Text(peer?.label ?? l10n.profileTitle),
        actions: [
          if (bundle != null && peer != null)
            IconButton(
              icon: const Icon(Icons.drive_file_rename_outline),
              tooltip: l10n.actionRenamePeer,
              onPressed: () => _rename(peer),
            ),
        ],
      ),
      body: ResponsiveContent(
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Text(l10n.profileLoadFailed, textAlign: TextAlign.center),
            ),
          ),
          data: (bundle) => bundle == null
              ? EmptyState(
                  icon: Icons.vpn_key_off,
                  title: l10n.profileNoneSavedTitle,
                  message: l10n.profileNoneSavedBody,
                )
              : ClientProfileBodyView(
                  serverId: widget.serverId,
                  rawConf: bundle.rawConf,
                  profile: bundle.profile,
                  network: server?.installation?.network,
                  profileExported: _profileExported,
                  clientImportDeclared: _clientImportDeclared,
                  confExpanded: _confExpanded,
                  onToggleConf: () =>
                      setState(() => _confExpanded = !_confExpanded),
                  onCopy: () => _copy(bundle.rawConf),
                  onShare: () => _share(bundle.rawConf),
                  onSave: () => _save(bundle.rawConf, peer),
                  onShowInstructions: () async {
                    final declared = await context.push<bool>(
                      importInstructionsPath(widget.serverId),
                    );
                    if (mounted && declared == true) {
                      setState(() => _clientImportDeclared = true);
                    }
                  },
                ),
        ),
      ),
    );
  }
}
