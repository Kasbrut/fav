import 'package:fav/core/theme/app_dimens.dart';
import 'package:fav/core/utils/relative_time.dart';
import 'package:fav/core/widgets/app_card.dart';
import 'package:fav/core/widgets/monospace_text.dart';
import 'package:fav/core/widgets/status_badge.dart';
import 'package:fav/features/servers/domain/server.dart';
import 'package:fav/features/servers/presentation/widgets/server_state_indicator.dart';
import 'package:fav/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// Actions offered by a [ServerCard]'s overflow menu.
enum _ServerCardAction { install, remove }

/// A card showing a registered server in the server list (spec §9.1).
class ServerCard extends StatelessWidget {
  /// Creates a [ServerCard] for [server].
  const ServerCard({
    required this.server,
    required this.onTap,
    this.onRemove,
    this.onInstall,
    super.key,
  });

  /// The server to display.
  final Server server;

  /// Called when the card is tapped.
  final VoidCallback onTap;

  /// Called to remove the server. When provided, an overflow menu offers a
  /// visible, keyboard- and screen-reader-accessible alternative to the
  /// swipe-to-delete gesture.
  final VoidCallback? onRemove;

  /// Called to install WireGuard on the server. Provided only while nothing
  /// is installed yet (failed install, or registered without installing).
  final VoidCallback? onInstall;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final metadata = server.metadata;
    final installed = server.installation != null;
    final hardened = server.installation?.hardeningApplied ?? false;
    return AppCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ServerStateIndicator(server: server),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  server.label,
                  style: theme.textTheme.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (onRemove != null || onInstall != null)
                PopupMenuButton<_ServerCardAction>(
                  icon: const Icon(Icons.more_vert),
                  padding: EdgeInsets.zero,
                  onSelected: (action) => switch (action) {
                    _ServerCardAction.install => onInstall!(),
                    _ServerCardAction.remove => onRemove!(),
                  },
                  itemBuilder: (context) => [
                    if (onInstall != null)
                      PopupMenuItem<_ServerCardAction>(
                        value: _ServerCardAction.install,
                        child: Row(
                          children: [
                            const Icon(Icons.download),
                            const SizedBox(width: AppSpacing.sm),
                            Flexible(
                              child: Text(
                                l10n.actionInstallWireguard,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (onRemove != null)
                      PopupMenuItem<_ServerCardAction>(
                        value: _ServerCardAction.remove,
                        child: Row(
                          children: [
                            Icon(
                              Icons.delete_outline,
                              color: theme.colorScheme.error,
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Text(l10n.actionRemoveServer),
                          ],
                        ),
                      ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          MonospaceText(
            '${server.username}@${server.host}:${server.sshPort}',
            selectable: false,
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    if (metadata != null)
                      StatusBadge(
                        label: '${metadata.osId} ${metadata.osVersion}',
                      ),
                    StatusBadge(
                      // The list only knows whether WireGuard is installed,
                      // not whether the tunnel is up; running/connected status
                      // lives on the detail screen. Reuse the detail screen's
                      // factual installed label for one consistent vocabulary.
                      label: hardened
                          ? l10n.statusHardened
                          : installed
                          ? l10n.statusWireguardInstalled
                          : l10n.statusNotInstalled,
                      variant: hardened
                          ? StatusBadgeVariant.success
                          : installed
                          ? StatusBadgeVariant.info
                          : StatusBadgeVariant.neutral,
                      icon: hardened
                          ? Icons.verified_user_outlined
                          : installed
                          ? Icons.shield_outlined
                          : Icons.dns_outlined,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                relativeTime(l10n, server.lastSeenAt),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
