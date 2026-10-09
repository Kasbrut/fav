import 'package:fav/core/theme/app_dimens.dart';
import 'package:fav/core/theme/app_semantic_colors.dart';
import 'package:fav/features/peers/domain/peer.dart';
import 'package:fav/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// Live-status hint used to drive the dot colour next to a peer's label.
enum PeerLiveStatus {
  /// Handshake within the recency window (< 3 min).
  online,

  /// Handshake older than the window, or never observed.
  offline,

  /// No live data — the monitor agent is unreachable or absent.
  unknown,
}

/// One row in the peers list: label, address, live status dot, overflow menu.
class PeerListTile extends StatelessWidget {
  /// Creates a [PeerListTile].
  const PeerListTile({
    required this.peer,
    required this.status,
    required this.onTap,
    required this.onRename,
    required this.onRevoke,
    super.key,
  });

  /// The peer to display.
  final Peer peer;

  /// Live-status hint, or [PeerLiveStatus.unknown] when no data is available.
  final PeerLiveStatus status;

  /// Called when the row is tapped (typically navigates to the detail).
  final VoidCallback onTap;

  /// Called when the user picks "Rename" from the overflow menu.
  final VoidCallback onRename;

  /// Called when the user picks "Revoke" from the overflow menu.
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final dot = _statusDot(context);
    // The dot conveys status by colour; pair it with a label so it reads for
    // screen readers and colour-blind users (the State-Never-Alone rule).
    final statusLabel = switch (status) {
      PeerLiveStatus.online => l10n.peerStatusOnline,
      PeerLiveStatus.offline => l10n.peerStatusOffline,
      PeerLiveStatus.unknown => null,
    };
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            if (dot != null && statusLabel != null) ...[
              Tooltip(
                message: statusLabel,
                child: Semantics(label: statusLabel, child: dot),
              ),
              const SizedBox(width: AppSpacing.md),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(peer.label, style: theme.textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    peer.address,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            PopupMenuButton<_PeerMenuAction>(
              tooltip: l10n.actionPeerOptions,
              onSelected: (action) {
                switch (action) {
                  case _PeerMenuAction.rename:
                    onRename();
                  case _PeerMenuAction.revoke:
                    onRevoke();
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: _PeerMenuAction.rename,
                  child: Text(l10n.actionRenamePeer),
                ),
                PopupMenuItem(
                  value: _PeerMenuAction.revoke,
                  // Revoke is destructive; mark it in the danger colour.
                  child: Text(
                    l10n.actionRevokePeer,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget? _statusDot(BuildContext context) {
    final theme = Theme.of(context);
    final color = switch (status) {
      PeerLiveStatus.online => context.semantic.success,
      PeerLiveStatus.offline => theme.colorScheme.onSurfaceVariant,
      PeerLiveStatus.unknown => null,
    };
    if (color == null) {
      return null;
    }
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }
}

enum _PeerMenuAction { rename, revoke }
