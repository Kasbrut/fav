import 'package:fav/core/theme/app_dimens.dart';
import 'package:fav/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// 16:9 placeholder rendered inside an instruction step card when no real
/// screenshot asset is available yet.
///
/// Screenshots are added later as static assets; this widget reserves the
/// visual slot so the layout does not jump when an image appears.
class ScreenshotPlaceholder extends StatelessWidget {
  /// Creates a [ScreenshotPlaceholder].
  const ScreenshotPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          border: Border.all(color: theme.colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(AppRadii.control),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.image_outlined,
                size: 40,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                l10n.instructionsScreenshotPlaceholder,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
