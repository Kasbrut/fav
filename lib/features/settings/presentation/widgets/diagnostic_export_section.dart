import 'package:fav/core/theme/app_dimens.dart';
import 'package:fav/core/widgets/app_card.dart';
import 'package:fav/features/settings/application/extended_diagnostic_provider.dart';
import 'package:fav/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// "Diagnostic" section on the Settings screen. Shows an expandable
/// "what's in / what's not" block and a button that copies the sanitized
/// bundle to the clipboard.
class DiagnosticExportSection extends ConsumerWidget {
  /// Creates the section.
  const DiagnosticExportSection({super.key});

  Future<void> _onCopy(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context);
    final messenger = ScaffoldMessenger.of(context);
    final bundle = await ref.read(extendedDiagnosticProvider)(uiLocale: locale);
    await Clipboard.setData(ClipboardData(text: bundle));
    if (!context.mounted) return;
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.settingsDiagnosticCopiedSnackbar)),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: EdgeInsets.zero,
            title: Text(l10n.settingsDiagnosticContentsHeader),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: AppSpacing.sm,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.settingsDiagnosticIncludedHeader,
                      style: theme.textTheme.labelMedium,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(l10n.settingsDiagnosticIncludedList),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      l10n.settingsDiagnosticExcludedHeader,
                      style: theme.textTheme.labelMedium,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      l10n.settingsDiagnosticExcludedList,
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          FilledButton.icon(
            icon: const Icon(Icons.copy),
            label: Text(l10n.settingsDiagnosticCopyButton),
            onPressed: () => _onCopy(context, ref),
          ),
        ],
      ),
    );
  }
}
