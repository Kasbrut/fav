import 'package:fav/core/theme/app_dimens.dart';
import 'package:flutter/material.dart';

/// A full-width, medium-emphasis secondary action button.
class SecondaryButton extends StatelessWidget {
  /// Creates a [SecondaryButton] labelled [label].
  const SecondaryButton({
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

  /// Whether to show a loading spinner and disable the button.
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: isLoading ? null : onPressed,
        child: isLoading
            ? SizedBox(
                width: AppSpacing.lg,
                height: AppSpacing.lg,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    Theme.of(context).colorScheme.primary,
                  ),
                ),
              )
            : icon == null
            ? Text(label)
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 18),
                  const SizedBox(width: AppSpacing.sm),
                  Text(label),
                ],
              ),
      ),
    );
  }
}
