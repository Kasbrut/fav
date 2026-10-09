import 'package:fav/core/router/app_router.dart';
import 'package:fav/core/theme/app_dimens.dart';
import 'package:fav/features/settings/presentation/widgets/wipe_confirmation_dialogs.dart';
import 'package:fav/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Danger zone section on the Settings screen. Single destructive action.
class DangerZoneSection extends ConsumerWidget {
  /// Creates the section.
  const DangerZoneSection({super.key});

  Future<void> _onWipe(BuildContext context, WidgetRef ref) async {
    final confirmed = await WipeConfirmationFlow.show(context);
    if (!confirmed || !context.mounted) return;
    // `go` replaces the whole stack with the post-wipe screen BEFORE any box
    // closes, so no mounted screen is left watching a box-backed provider
    // while the wipe runs (audit M11). The screen itself performs the wipe
    // and shows its outcome. `extra: true` is the confirmation token the
    // route guard requires — without it the route bounces to the server
    // list, so a platform-injected `/post-wipe` cannot wipe (audit H1).
    context.go(postWipeRoute, extra: true);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.errorContainer,
      borderRadius: BorderRadius.circular(AppRadii.card),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.settingsScriptsBody,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: theme.colorScheme.onErrorContainer,
                side: BorderSide(color: theme.colorScheme.error),
              ),
              icon: const Icon(Icons.description_outlined),
              label: Text(l10n.settingsScriptsButton),
              onPressed: () => context.push(settingsScriptsRoute),
            ),
            Divider(
              height: AppSpacing.xl,
              color: theme.colorScheme.onErrorContainer.withValues(alpha: 0.2),
            ),
            Text(
              l10n.settingsWipeDialog1Body,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.error,
                foregroundColor: theme.colorScheme.onError,
              ),
              icon: const Icon(Icons.delete_forever),
              label: Text(l10n.settingsWipeButton),
              onPressed: () => _onWipe(context, ref),
            ),
          ],
        ),
      ),
    );
  }
}
