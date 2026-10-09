import 'package:fav/core/theme/app_semantic_colors.dart';
import 'package:fav/features/servers/domain/server.dart';
import 'package:fav/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// Persistent configuration state shown beside a server name.
class ServerStateIndicator extends StatelessWidget {
  /// Creates an indicator for [server].
  const ServerStateIndicator({required this.server, super.key});

  /// Server whose configuration state is represented.
  final Server server;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final installation = server.installation;
    final hardened = installation?.hardeningApplied ?? false;
    final (label, icon, foreground, background) = installation == null
        ? (
            l10n.statusNotInstalled,
            Icons.dns_outlined,
            scheme.onSurfaceVariant,
            scheme.surfaceContainerHighest,
          )
        : hardened
        ? (
            l10n.statusHardened,
            Icons.verified_user_outlined,
            context.semantic.success,
            context.semantic.successSurface,
          )
        : (
            l10n.statusWireguardInstalled,
            Icons.shield_outlined,
            context.semantic.info,
            context.semantic.infoSurface,
          );
    return Tooltip(
      message: label,
      child: Semantics(
        label: label,
        image: true,
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: ExcludeSemantics(
            child: Icon(icon, size: 18, color: foreground),
          ),
        ),
      ),
    );
  }
}
