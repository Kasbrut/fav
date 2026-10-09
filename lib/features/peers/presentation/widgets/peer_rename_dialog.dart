import 'package:fav/core/theme/app_dimens.dart';
import 'package:fav/core/utils/validators.dart';
import 'package:fav/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// Shows a rename dialog seeded with [currentLabel].
///
/// Returns the validated new label, or `null` when the user cancels.
Future<String?> showPeerRenameDialog({
  required BuildContext context,
  required String currentLabel,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _PeerRenameDialog(currentLabel: currentLabel),
  );
}

class _PeerRenameDialog extends StatefulWidget {
  const _PeerRenameDialog({required this.currentLabel});
  final String currentLabel;

  @override
  State<_PeerRenameDialog> createState() => _PeerRenameDialogState();
}

class _PeerRenameDialogState extends State<_PeerRenameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.currentLabel,
  );
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final l10n = AppLocalizations.of(context)!;
    final value = _controller.text.trim();
    if (!isValidPeerLabel(value)) {
      setState(() => _error = l10n.errPeerLabelInvalid);
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l10n.peerRenameDialogTitle),
      content: Padding(
        padding: const EdgeInsets.only(top: AppSpacing.sm),
        child: TextField(
          controller: _controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: l10n.addPeerLabelLabel,
            errorText: _error,
          ),
          onChanged: (_) {
            if (_error != null) {
              setState(() => _error = null);
            }
          },
          onSubmitted: (_) => _submit(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.actionCancel),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(l10n.actionConfirm),
        ),
      ],
    );
  }
}
