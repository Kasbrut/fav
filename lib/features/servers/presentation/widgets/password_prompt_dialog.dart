import 'package:fav/core/theme/app_dimens.dart';
import 'package:fav/core/widgets/app_text_field.dart';
import 'package:fav/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// Shows a dialog asking for the SSH password for [target].
///
/// Returns the entered password, or `null` if the user cancelled. Passwords
/// are requested on demand and never stored (spec RF-20).
Future<String?> showPasswordPrompt(BuildContext context, String target) {
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _PasswordPromptDialog(target: target),
  );
}

class _PasswordPromptDialog extends StatefulWidget {
  const _PasswordPromptDialog({required this.target});

  final String target;

  @override
  State<_PasswordPromptDialog> createState() => _PasswordPromptDialogState();
}

class _PasswordPromptDialogState extends State<_PasswordPromptDialog> {
  final _controller = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    // Best-effort: drop the password text before releasing the controller.
    _controller
      ..clear()
      ..dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    final password = _controller.text;
    setState(() => _isSubmitting = true);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.of(context).pop(password);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l10n.passwordPromptTitle),
      content: AbsorbPointer(
        absorbing: _isSubmitting,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.passwordPromptBody(widget.target)),
            const SizedBox(height: AppSpacing.lg),
            AppTextField(
              label: l10n.fieldPassword,
              controller: _controller,
              obscureText: true,
              autofocus: true,
              onFieldSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              l10n.passwordPromptHint,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.actionCancel),
        ),
        FilledButton(
          onPressed: _isSubmitting ? null : _submit,
          child: _isSubmitting
              ? SizedBox(
                  width: AppSpacing.lg,
                  height: AppSpacing.lg,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Theme.of(context).colorScheme.onPrimary,
                    ),
                  ),
                )
              : Text(l10n.actionConfirm),
        ),
      ],
    );
  }
}
