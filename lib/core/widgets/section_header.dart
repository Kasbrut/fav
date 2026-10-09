import 'package:fav/core/theme/app_dimens.dart';
import 'package:flutter/material.dart';

/// An uppercase, muted heading that introduces a group of related content.
///
/// Matches the `NOME SERVER` / `WIREGUARD` / `SISTEMA` style of the mockups.
class SectionHeader extends StatelessWidget {
  /// Creates a [SectionHeader] with the given [label].
  const SectionHeader({required this.label, this.hint, super.key});

  /// The section title; rendered in upper case.
  final String label;

  /// Optional supporting line shown below the [label].
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            letterSpacing: 0.6,
          ),
        ),
        if (hint != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            hint!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}
