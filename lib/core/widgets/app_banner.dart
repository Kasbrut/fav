import 'package:fav/core/theme/app_dimens.dart';
import 'package:fav/core/theme/app_semantic_colors.dart';
import 'package:flutter/material.dart';

/// Semantic colour variants for an [AppBanner].
enum AppBannerVariant {
  /// A neutral, informational message.
  info,

  /// A cautionary message.
  warning,

  /// A failure or destructive message.
  danger,

  /// A positive confirmation message.
  success,
}

/// A tinted, bordered callout that highlights a contextual message.
class AppBanner extends StatelessWidget {
  /// Creates an [AppBanner] showing [message].
  const AppBanner({
    required this.message,
    this.variant = AppBannerVariant.info,
    this.icon,
    this.title,
    this.action,
    super.key,
  });

  /// The banner body text.
  final String message;

  /// The semantic colour variant.
  final AppBannerVariant variant;

  /// Optional leading icon.
  final IconData? icon;

  /// Optional emphasised title shown above [message].
  final String? title;

  /// Optional trailing action widget (e.g. a button).
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final semantic = context.semantic;
    final (
      Color background,
      Color foreground,
      Color border,
    ) = switch (variant) {
      AppBannerVariant.info => (
        semantic.infoSurface,
        semantic.info,
        semantic.info,
      ),
      AppBannerVariant.warning => (
        semantic.warningSurface,
        semantic.warning,
        semantic.warningBorder,
      ),
      AppBannerVariant.danger => (
        scheme.errorContainer,
        scheme.error,
        scheme.error,
      ),
      AppBannerVariant.success => (
        semantic.successSurface,
        semantic.success,
        semantic.success,
      ),
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadii.control),
        border: Border.all(color: border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: AppSizes.statusIcon, color: foreground),
            const SizedBox(width: AppSpacing.sm),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null) ...[
                  Text(
                    title!,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: foreground,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                ],
                Text(
                  message,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurface,
                  ),
                ),
                if (action != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Align(alignment: Alignment.centerRight, child: action),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
