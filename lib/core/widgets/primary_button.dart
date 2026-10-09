import 'package:fav/core/theme/app_dimens.dart';
import 'package:flutter/material.dart';

/// A full-width, high-emphasis primary action button.
///
/// When [isLoading] is true the button shows a spinner and is disabled.
class PrimaryButton extends StatelessWidget {
  /// Creates a [PrimaryButton] labelled [label].
  const PrimaryButton({
    required this.label,
    this.onPressed,
    this.icon,
    this.isLoading = false,
    super.key,
  });

  /// The button label.
  final String label;

  /// Called when the button is pressed; null disables the button.
  final VoidCallback? onPressed;

  /// Optional leading icon.
  final IconData? icon;

  /// Whether to show a loading spinner instead of the label.
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: isLoading ? null : onPressed,
        child: isLoading
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
            : _PrimaryButtonLabel(label: label, icon: icon),
      ),
    );
  }
}

/// The label-and-optional-icon content of a [PrimaryButton].
class _PrimaryButtonLabel extends StatelessWidget {
  const _PrimaryButtonLabel({required this.label, this.icon});

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    if (icon == null) {
      return Text(label);
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: AppSpacing.sm),
        Text(label),
      ],
    );
  }
}
