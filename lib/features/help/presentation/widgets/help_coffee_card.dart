import 'package:fav/core/theme/app_dimens.dart';
import 'package:flutter/material.dart';

/// A warm, visually distinct entry point for the optional coffee page.
class HelpCoffeeCard extends StatelessWidget {
  /// Creates the card.
  const HelpCoffeeCard({
    required this.title,
    required this.subtitle,
    required this.onTap,
    super.key,
  });

  /// Localized question shown as the card heading.
  final String title;

  /// Localized supporting text.
  final String subtitle;

  /// Opens the coffee page.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final radius = BorderRadius.circular(AppRadii.large);

    return Material(
      color: colors.tertiaryContainer,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: colors.tertiary.withValues(alpha: 0.28)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            children: [
              Container(
                width: AppSizes.minTouchTarget,
                height: AppSizes.minTouchTarget,
                decoration: BoxDecoration(
                  color: colors.tertiary,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.local_cafe_outlined,
                  color: colors.onTertiary,
                ),
              ),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: colors.onTertiaryContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onTertiaryContainer.withValues(
                          alpha: 0.82,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Icon(
                Icons.arrow_forward_rounded,
                color: colors.onTertiaryContainer,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
