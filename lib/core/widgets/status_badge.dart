import 'package:fav/core/theme/app_dimens.dart';
import 'package:fav/core/theme/app_semantic_colors.dart';
import 'package:flutter/material.dart';

/// Semantic colour variants for a [StatusBadge].
enum StatusBadgeVariant {
  /// A positive/healthy state (e.g. WireGuard active).
  success,

  /// A cautionary state (e.g. installation in progress).
  warning,

  /// A failure state (e.g. SSH error).
  danger,

  /// A plain, non-semantic label (e.g. an OS name).
  neutral,

  /// An informational state.
  info,
}

/// A small rounded pill conveying a status, matching the mockup badges.
class StatusBadge extends StatelessWidget {
  /// Creates a [StatusBadge] with the given [label].
  const StatusBadge({
    required this.label,
    this.variant = StatusBadgeVariant.neutral,
    this.icon,
    super.key,
  });

  /// The badge text.
  final String label;

  /// The semantic colour variant.
  final StatusBadgeVariant variant;

  /// Optional leading icon.
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final semantic = context.semantic;
    final (Color background, Color foreground) = switch (variant) {
      StatusBadgeVariant.success => (semantic.successSurface, semantic.success),
      StatusBadgeVariant.warning => (semantic.warningSurface, semantic.warning),
      StatusBadgeVariant.danger => (scheme.errorContainer, scheme.error),
      StatusBadgeVariant.info => (semantic.infoSurface, semantic.info),
      StatusBadgeVariant.neutral => (
        scheme.surfaceContainerHighest,
        scheme.onSurfaceVariant,
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadii.badge),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: foreground),
            const SizedBox(width: AppSpacing.xs),
          ],
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(color: foreground),
          ),
        ],
      ),
    );
  }
}
