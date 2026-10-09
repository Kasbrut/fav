import 'package:fav/core/theme/app_dimens.dart';
import 'package:flutter/material.dart';

/// A centred placeholder shown when a screen has no content to display.
///
/// Also serves as the error/message view, with [icon] omitted.
class EmptyState extends StatelessWidget {
  /// Creates an [EmptyState].
  const EmptyState({
    required this.title,
    this.icon,
    this.message,
    this.action,
    super.key,
  });

  /// The primary line of text.
  final String title;

  /// Optional illustration icon shown above [title].
  final IconData? icon;

  /// Optional supporting line shown below [title].
  final String? message;

  /// Optional action widget shown below the text.
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: AppSizes.emptyStateIcon,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
            Text(
              title,
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            if (message != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                message!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: AppSpacing.xl),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
