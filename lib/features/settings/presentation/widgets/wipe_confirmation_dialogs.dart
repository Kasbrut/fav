import 'package:fav/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// Two-step confirmation dialog for the wipe flow. Returns `true` only when
/// the user clears both dialogs by typing the localized confirm word.
class WipeConfirmationFlow {
  /// Runs the sequence inside [context]. Returns `false` on any cancel.
  static Future<bool> show(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final firstOk = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.settingsWipeDialog1Title),
        content: Text(l10n.settingsWipeDialog1Body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.settingsWipeDialog1Cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.settingsWipeDialog1Continue),
          ),
        ],
      ),
    );
    if (firstOk != true || !context.mounted) return false;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => const _WipeConfirmDialog(),
    );
    return confirmed == true;
  }
}

/// Second wipe dialog: requires typing the localized confirm word. It owns its
/// [TextEditingController] in [State] so the controller is disposed only when
/// the dialog route is fully gone — disposing it eagerly right after
/// `showDialog` returns crashes when the dialog's exit transition rebuilds the
/// field (a `ChangeNotifier` used after dispose, cascading into a RenderFlex
/// overflow and a `_dependents.isEmpty` assertion).
class _WipeConfirmDialog extends StatefulWidget {
  const _WipeConfirmDialog();

  @override
  State<_WipeConfirmDialog> createState() => _WipeConfirmDialogState();
}

class _WipeConfirmDialogState extends State<_WipeConfirmDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final word = l10n.settingsWipeConfirmWord;
    return AlertDialog(
      title: Text(l10n.settingsWipeDialog2Title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.settingsWipeDialog2Body(word)),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            autofocus: true,
            decoration: const InputDecoration(border: OutlineInputBorder()),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.settingsWipeDialog2Cancel),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Theme.of(context).colorScheme.onError,
          ),
          onPressed: _controller.text == word
              ? () => Navigator.of(context).pop(true)
              : null,
          child: Text(l10n.settingsWipeDialog2Action),
        ),
      ],
    );
  }
}
