import 'package:fav/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// Shows a destructive confirm dialog for revoking a peer.
///
/// Returns `true` when the user confirms, `false` (or `null`) otherwise.
Future<bool?> showPeerRevokeConfirmDialog({required BuildContext context}) {
  final l10n = AppLocalizations.of(context)!;
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.peerRevokeConfirmTitle),
      content: Text(l10n.peerRevokeConfirmBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.actionCancel),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Theme.of(context).colorScheme.onError,
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.peerRevokeConfirmAction),
        ),
      ],
    ),
  );
}
