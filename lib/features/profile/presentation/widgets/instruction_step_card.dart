import 'package:fav/core/theme/app_dimens.dart';
import 'package:fav/core/widgets/app_card.dart';
import 'package:fav/features/profile/presentation/widgets/instruction_store_links.dart';
import 'package:flutter/material.dart';

/// A single numbered step in the import-instructions flow.
///
/// Renders a numeric badge, a short title, a description, and an optional
/// supporting action or screenshot.
class InstructionStepCard extends StatelessWidget {
  /// Creates an [InstructionStepCard].
  const InstructionStepCard({
    required this.number,
    required this.title,
    required this.description,
    this.screenshotAsset,
    this.storeLinks = const [],
    super.key,
  });

  /// 1-based ordinal shown in the badge.
  final int number;

  /// Short step title.
  final String title;

  /// Longer step description, one or two plain sentences.
  final String description;

  /// Optional asset path for a supporting screenshot.
  final String? screenshotAsset;

  /// Store links shown in place of a screenshot for the "install" steps. When
  /// non-empty these take precedence over [screenshotAsset] and the
  /// placeholder. Defaults to an empty list.
  final List<WireguardStore> storeLinks;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _StepBadge(number: number),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            description,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.md),
          if (storeLinks.isNotEmpty)
            InstructionStoreLinks(stores: storeLinks)
          else if (screenshotAsset != null)
            Align(
              alignment: Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadii.control),
                  child: Image.asset(
                    screenshotAsset!,
                    fit: BoxFit.contain,
                    excludeFromSemantics: true,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _StepBadge extends StatelessWidget {
  const _StepBadge({required this.number});

  final int number;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: theme.colorScheme.primary,
        shape: BoxShape.circle,
      ),
      child: Text(
        '$number',
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.onPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
