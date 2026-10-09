import 'package:fav/core/errors/app_exception.dart';
import 'package:fav/core/errors/error_messages.dart';
import 'package:fav/core/theme/app_dimens.dart';
import 'package:fav/core/widgets/app_card.dart';
import 'package:fav/core/widgets/responsive_app_bar.dart';
import 'package:fav/core/widgets/responsive_content.dart';
import 'package:fav/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// Detail card for a single [ErrorCode] — shows the message, cause, fix.
class TroubleshootingDetailScreen extends StatelessWidget {
  /// Creates the screen.
  const TroubleshootingDetailScreen({required this.code, super.key});

  /// `ErrorCode.id` value from the URL parameter (e.g. `ERR-CONN-01`).
  final String code;

  ErrorCode? _resolve() {
    for (final c in ErrorCode.values) {
      if (c.id == code) return c;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final resolved = _resolve();
    if (resolved == null) {
      return Scaffold(
        appBar: ResponsiveAppBar(
          title: code,
          maxContentWidth: AppSizes.contentMaxWidth,
        ),
        body: Center(child: Text(l10n.helpTroubleshootingTitle)),
      );
    }
    final theme = Theme.of(context);
    return Scaffold(
      appBar: ResponsiveAppBar(
        title: resolved.id,
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
            _Section(
              title: l10n.helpTroubleshootingWhatHappened,
              body: localizedErrorMessage(l10n, resolved),
              theme: theme,
            ),
            const SizedBox(height: AppSpacing.md),
            _Section(
              title: l10n.helpTroubleshootingWhyHappens,
              body: localizedErrorCause(l10n, resolved),
              theme: theme,
            ),
            const SizedBox(height: AppSpacing.md),
            _Section(
              title: l10n.helpTroubleshootingHowToFix,
              body: localizedErrorFix(l10n, resolved),
              theme: theme,
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.body,
    required this.theme,
  });
  final String title;
  final String body;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleSmall),
            const SizedBox(height: AppSpacing.sm),
            Text(body, style: theme.textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}
