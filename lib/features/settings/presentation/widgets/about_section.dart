import 'package:fav/core/theme/app_dimens.dart';
import 'package:fav/core/widgets/app_card.dart';
import 'package:fav/features/help/presentation/external_link.dart';
import 'package:fav/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

const String _sourceCodeUrl = 'https://github.com/Kasbrut/fav';

/// "About" card on the Settings screen. Shows the app title + version,
/// then three tappable rows: licenses, privacy, source code.
class AboutSection extends StatelessWidget {
  /// Creates the section.
  const AboutSection({super.key});

  Future<String> _version() async {
    try {
      final pkg = await PackageInfo.fromPlatform();
      return '${pkg.version}+${pkg.buildNumber}';
    } on Object {
      return 'unknown';
    }
  }

  Future<void> _showPrivacy(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.settingsPrivacyDialogTitle),
        content: SingleChildScrollView(
          child: Text(l10n.settingsPrivacyDialogBody),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.settingsPrivacyDialogClose),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.appTitle, style: theme.textTheme.titleMedium),
          Text(
            l10n.settingsFullName,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          FutureBuilder<String>(
            future: _version(),
            builder: (context, snap) => Text(
              '${l10n.settingsVersionLabel} ${snap.data ?? '…'}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.settingsLicensesTile),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showLicensePage(
              context: context,
              applicationName: l10n.appTitle,
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.settingsPrivacyTile),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showPrivacy(context),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.settingsSourceTile),
            trailing: const Icon(Icons.open_in_new),
            onTap: () => confirmAndLaunchExternal(
              context,
              Uri.parse(_sourceCodeUrl),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            l10n.settingsAboutBody,
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}
