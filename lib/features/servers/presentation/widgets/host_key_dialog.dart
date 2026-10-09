import 'package:fav/core/router/app_router.dart';
import 'package:fav/core/theme/app_dimens.dart';
import 'package:fav/core/widgets/monospace_text.dart';
import 'package:fav/features/install/data/ssh/host_key_store.dart';
import 'package:fav/features/install/domain/ssh_client.dart';
import 'package:fav/features/servers/domain/host_key_fingerprint.dart';
import 'package:fav/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Shared handler for a [HostKeyUnknownException] raised mid-operation:
/// shows the explicit confirmation dialog (with the trusted-before copy for
/// a legacy MD5-era pin needing re-confirmation after the SHA-256
/// migration), pins the fingerprint on confirm, and returns whether the
/// caller should retry the operation. Every interactive SSH entry point
/// funnels through this, so the wall and the door always come together
/// (audit M3 — hit live from Add peer as a misleading "cannot reach").
Future<bool> confirmPendingHostKey(
  BuildContext context,
  WidgetRef ref,
  HostKeyUnknownException pending,
) async {
  final trusted = await showHostKeyDialog(
    context,
    pending.fingerprint,
    previouslyTrusted: pending.previouslyTrusted,
  );
  if (trusted ?? false) {
    await ref.read(hostKeyStoreProvider).pin(pending.fingerprint);
    return true;
  }
  return false;
}

/// Shows the Trust-On-First-Use host key confirmation dialog (spec §10).
///
/// The dialog explains that the app remembers the server's identity and warns
/// on any later change, and shows the key type + algorithm-labelled fingerprint
/// inline so the user can verify it (spec §10); only the longer explanatory
/// hint and glossary link stay behind an opt-in disclosure. Returns `true` when
/// the user proceeds, `false` or `null` otherwise.
Future<bool?> showHostKeyDialog(
  BuildContext context,
  HostKeyFingerprint fingerprint, {
  bool previouslyTrusted = false,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _HostKeyDialog(
      fingerprint: fingerprint,
      previouslyTrusted: previouslyTrusted,
    ),
  );
}

/// Shows the deliberate host-key rotation confirmation. Both trust anchors
/// stay visible so the user can verify the new value out of band before the
/// destructive replacement; ordinary mismatch errors never open this dialog.
Future<bool?> showHostKeyReplacementDialog(
  BuildContext context, {
  required HostKeyFingerprint current,
  required HostKeyFingerprint replacement,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      constraints: const BoxConstraints(maxWidth: AppSizes.dialogMaxWidth),
      title: Text(AppLocalizations.of(context)!.hostKeyReplaceTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(AppLocalizations.of(context)!.hostKeyReplaceBody),
          const SizedBox(height: AppSpacing.lg),
          _DialogField(
            label: AppLocalizations.of(context)!.hostKeyReplaceCurrent,
            value:
                '${current.hashAlgorithm.toUpperCase()}:'
                '${current.fingerprint}',
          ),
          const SizedBox(height: AppSpacing.md),
          _DialogField(
            label: AppLocalizations.of(context)!.hostKeyReplaceNew,
            value:
                '${replacement.hashAlgorithm.toUpperCase()}:'
                '${replacement.fingerprint}',
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(AppLocalizations.of(context)!.actionCancel),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Theme.of(context).colorScheme.onError,
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(AppLocalizations.of(context)!.hostKeyReplaceConfirm),
        ),
      ],
    ),
  );
}

class _HostKeyDialog extends StatefulWidget {
  const _HostKeyDialog({
    required this.fingerprint,
    required this.previouslyTrusted,
  });

  final HostKeyFingerprint fingerprint;
  final bool previouslyTrusted;

  @override
  State<_HostKeyDialog> createState() => _HostKeyDialogState();
}

class _HostKeyDialogState extends State<_HostKeyDialog> {
  bool _showDetails = false;

  void _toggleDetails() => setState(() => _showDetails = !_showDetails);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final fingerprint = widget.fingerprint;
    return AlertDialog(
      constraints: const BoxConstraints(maxWidth: AppSizes.dialogMaxWidth),
      title: Text(l10n.hostKeyTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // A legacy (MD5-era) pin being re-confirmed must not claim a
          // first connection: that copy would suppress exactly the
          // suspicion an MITM wants suppressed (security audit M1).
          Text(
            widget.previouslyTrusted
                ? l10n.hostKeyBodyRepin(fingerprint.host)
                : l10n.hostKeyBody(fingerprint.host),
          ),
          const SizedBox(height: AppSpacing.md),
          // Show the server's identity explicitly (spec §10 requires the
          // fingerprint be shown, not hidden behind a disclosure). The
          // fingerprint is labelled with its hash algorithm (SHA-256 since
          // dartssh2 3.x) and rendered in the exact OpenSSH format that
          // `ssh-keygen -lf <hostkey>.pub` prints, so the user can compare
          // it verbatim (audit L1 / M-md5, closed by the 3.x migration).
          _DialogField(
            label: l10n.hostKeyFieldType,
            value: fingerprint.keyType,
          ),
          const SizedBox(height: AppSpacing.sm),
          _DialogField(
            label: l10n.hostKeyFieldFingerprint,
            value:
                '${fingerprint.hashAlgorithm.toUpperCase()}:'
                '${fingerprint.fingerprint}',
          ),
          const SizedBox(height: AppSpacing.xs),
          // The explanatory hint / glossary link stays opt-in.
          InkWell(
            onTap: _toggleDetails,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Row(
                children: [
                  Icon(
                    _showDetails ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    l10n.hostKeyVerifyToggle,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_showDetails) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              l10n.hostKeyVerifyHint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => context.push(glossaryEntryPath('fingerprint')),
                icon: const Icon(Icons.info_outline, size: 18),
                label: Text(l10n.hostKeyWhatIsThis),
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.actionCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.actionConnect),
        ),
      ],
    );
  }
}

class _DialogField extends StatelessWidget {
  const _DialogField({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        // Left selectable (the widget's default) so the user can copy the
        // fingerprint to compare it against their provider's console.
        MonospaceText(value),
      ],
    );
  }
}
