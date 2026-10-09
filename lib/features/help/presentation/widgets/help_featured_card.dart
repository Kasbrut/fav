import 'package:fav/core/theme/app_dimens.dart';
import 'package:flutter/material.dart';

/// The "Quick Start" featured card on top of `HelpHubScreen`. Larger and
/// visually distinct from a plain category tile.
class HelpFeaturedCard extends StatelessWidget {
  /// Creates a featured card.
  const HelpFeaturedCard({
    required this.title,
    required this.body,
    required this.ctaLabel,
    required this.onTap,
    super.key,
  });

  /// Localized headline.
  final String title;

  /// Localized supporting body text (1-2 lines).
  final String body;

  /// Localized CTA button label (e.g. "Start").
  final String ctaLabel;

  /// Tap handler.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.primaryContainer,
      borderRadius: BorderRadius.circular(AppRadii.large),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.large),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: theme.textTheme.titleLarge?.copyWith(
                  color: theme.colorScheme.onPrimaryContainer,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                body,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onPrimaryContainer,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: AppSpacing.lg),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: onTap,
                  icon: const Icon(Icons.arrow_forward),
                  label: Text(ctaLabel),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
