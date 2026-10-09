import 'package:fav/core/crypto/ssh_public_key.dart';
import 'package:fav/core/theme/app_dimens.dart';
import 'package:fav/core/utils/validators.dart';
import 'package:fav/core/widgets/app_card.dart';
import 'package:fav/core/widgets/monospace_text.dart';
import 'package:fav/features/servers/data/ssh_key_file_importer.dart';
import 'package:fav/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A card listing the user's SSH public keys with add/remove affordances.
///
/// Presentation-only: the host wires [onAdd] and [onRemove] to either an
/// in-memory list (the advanced install form) or a live SSH operation (the
/// server detail screen). Keys are normalized OpenSSH `authorized_keys` lines.
class SshKeyListCard extends StatelessWidget {
  /// Creates an [SshKeyListCard].
  const SshKeyListCard({
    required this.keys,
    required this.onAdd,
    required this.onRemove,
    this.busy = false,
    super.key,
  });

  /// The keys currently configured (normalized `authorized_keys` lines).
  final List<String> keys;

  /// Called when the user asks to add a key.
  final VoidCallback onAdd;

  /// Called when the user removes [key].
  final void Function(String key) onRemove;

  /// Whether an operation is in flight; disables the buttons.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (keys.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Text(
                l10n.sshKeysEmpty,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else
            for (var i = 0; i < keys.length; i++) ...[
              if (i > 0) const Divider(height: 1),
              _SshKeyRow(
                line: keys[i],
                onRemove: busy ? null : () => onRemove(keys[i]),
              ),
            ],
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: busy ? null : onAdd,
              icon: const Icon(Icons.add, size: 18),
              label: Text(l10n.actionAddSshKey),
            ),
          ),
        ],
      ),
    );
  }
}

/// One key row: type, optional comment and fingerprint, with a delete button.
class _SshKeyRow extends StatelessWidget {
  const _SshKeyRow({required this.line, required this.onRemove});

  final String line;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final parsed = SshPublicKey.tryParse(line);
    final title = parsed == null
        ? line
        : (parsed.comment.isEmpty ? parsed.algorithm : parsed.comment);
    final subtitle = parsed?.fingerprint ?? '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodyMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xs),
                  MonospaceText(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            onPressed: onRemove,
            icon: const Icon(Icons.delete_outline),
            tooltip: l10n.actionRemove,
          ),
        ],
      ),
    );
  }
}

/// Shows the add-key dialog and returns the normalized `authorized_keys` line
/// the user entered (by paste or file import), or `null` when cancelled.
Future<String?> showAddSshKeyDialog(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (context) => const _AddSshKeyDialog(),
  );
}

class _AddSshKeyDialog extends ConsumerStatefulWidget {
  const _AddSshKeyDialog();

  @override
  ConsumerState<_AddSshKeyDialog> createState() => _AddSshKeyDialogState();
}

class _AddSshKeyDialogState extends ConsumerState<_AddSshKeyDialog> {
  final _formKey = GlobalKey<FormState>();
  final _controller = TextEditingController();
  String? _importError;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _import() async {
    final l10n = AppLocalizations.of(context)!;
    try {
      final content = await ref.read(sshKeyFileImporterProvider)();
      if (content == null || !mounted) {
        return;
      }
      setState(() {
        _controller.text = content.trim();
        _importError = null;
      });
      // Surface invalid imported files immediately rather than only on submit.
      _formKey.currentState?.validate();
    } on Object {
      if (mounted) {
        setState(() => _importError = l10n.sshKeyImportFailed);
      }
    }
  }

  void _submit() {
    if (_formKey.currentState?.validate() ?? false) {
      // Normalize before returning so storage and the server see one canonical
      // line regardless of the surrounding whitespace the user pasted.
      final parsed = SshPublicKey.tryParse(_controller.text);
      Navigator.of(context).pop(parsed?.line);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l10n.sshKeyAddTitle),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextFormField(
              controller: _controller,
              autofocus: true,
              minLines: 2,
              maxLines: 5,
              decoration: InputDecoration(
                labelText: l10n.sshKeyFieldLabel,
                hintText: l10n.sshKeyFieldHint,
                errorText: _importError,
              ),
              validator: (value) => isValidSshPublicKey(value?.trim() ?? '')
                  ? null
                  : l10n.validationSshPublicKey,
              autovalidateMode: AutovalidateMode.onUserInteraction,
            ),
            const SizedBox(height: AppSpacing.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _import,
                icon: const Icon(Icons.upload_file, size: 18),
                label: Text(l10n.actionImportFromFile),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.actionCancel),
        ),
        FilledButton(onPressed: _submit, child: Text(l10n.actionAdd)),
      ],
    );
  }
}
