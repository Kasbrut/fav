import 'package:fav/core/theme/app_dimens.dart';
import 'package:fav/core/widgets/responsive_app_bar.dart';
import 'package:fav/features/help/presentation/widgets/help_category_tile.dart';
import 'package:fav/features/help/presentation/widgets/help_coffee_card.dart';
import 'package:fav/features/help/presentation/widgets/help_featured_card.dart';
import 'package:fav/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Hub of the Help tab — featured Quick Start card plus 7 category rows.
class HelpHubScreen extends StatelessWidget {
  /// Creates the help hub.
  const HelpHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: ResponsiveAppBar(
        title: l10n.helpTitle,
        maxContentWidth: AppSizes.contentMaxWidth,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: AppSizes.contentMaxWidth,
          ),
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              HelpFeaturedCard(
                title: l10n.helpHubQuickStartTitle,
                body: l10n.helpHubQuickStartBody,
                ctaLabel: l10n.helpHubQuickStartCta,
                onTap: () => context.push('/help/getting-started'),
              ),
              const SizedBox(height: AppSpacing.lg),
              HelpCategoryTile(
                icon: Icons.menu_book,
                title: l10n.helpHubGlossary,
                subtitle: l10n.helpHubGlossarySubtitle,
                onTap: () => context.push('/help/glossary'),
              ),
              const SizedBox(height: AppSpacing.sm),
              HelpCategoryTile(
                icon: Icons.error_outline,
                title: l10n.helpHubErrors,
                subtitle: l10n.helpHubErrorsSubtitle,
                onTap: () => context.push('/help/errors'),
              ),
              const SizedBox(height: AppSpacing.sm),
              HelpCategoryTile(
                icon: Icons.lock_outline,
                title: l10n.helpHubFirewall,
                subtitle: l10n.helpHubFirewallSubtitle,
                onTap: () => context.push('/help/firewall'),
              ),
              const SizedBox(height: AppSpacing.sm),
              HelpCategoryTile(
                icon: Icons.help_outline,
                title: l10n.helpHubFaq,
                subtitle: l10n.helpHubFaqSubtitle,
                onTap: () => context.push('/help/faq'),
              ),
              const SizedBox(height: AppSpacing.sm),
              HelpCategoryTile(
                icon: Icons.link,
                title: l10n.helpHubResources,
                subtitle: l10n.helpHubResourcesSubtitle,
                onTap: () => context.push('/help/resources'),
              ),
              const SizedBox(height: AppSpacing.sm),
              HelpCategoryTile(
                icon: Icons.bug_report_outlined,
                title: l10n.helpHubReportIssue,
                subtitle: l10n.helpHubReportIssueSubtitle,
                onTap: () => context.push('/help/report-issue'),
              ),
              const SizedBox(height: AppSpacing.sm),
              HelpCoffeeCard(
                title: l10n.helpHubDonate,
                subtitle: l10n.helpHubDonateSubtitle,
                onTap: () => context.push('/help/donate'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
