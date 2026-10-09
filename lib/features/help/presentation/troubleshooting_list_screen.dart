import 'package:fav/core/errors/app_exception.dart';
import 'package:fav/core/errors/error_messages.dart';
import 'package:fav/core/theme/app_dimens.dart';
import 'package:fav/core/widgets/responsive_app_bar.dart';
import 'package:fav/core/widgets/responsive_content.dart';
import 'package:fav/features/help/presentation/widgets/help_category_tile.dart';
import 'package:fav/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Lists every [ErrorCode] with its `ERR-xx` id + short message.
class TroubleshootingListScreen extends StatelessWidget {
  /// Creates the screen.
  const TroubleshootingListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: ResponsiveAppBar(
        title: l10n.helpTroubleshootingTitle,
        maxContentWidth: AppSizes.contentMaxWidth,
      ),
      body: ResponsiveContent(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.xxl,
          ),
          children: [
            for (final code in ErrorCode.values) ...[
              HelpCategoryTile(
                icon: Icons.error_outline,
                title: code.id,
                subtitle: localizedErrorMessage(l10n, code),
                onTap: () => context.push('/help/errors/${code.id}'),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
          ],
        ),
      ),
    );
  }
}
