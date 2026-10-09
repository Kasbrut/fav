import 'package:fav/core/router/app_router.dart';
import 'package:fav/core/theme/app_dimens.dart';
import 'package:fav/core/widgets/app_card.dart';
import 'package:fav/core/widgets/responsive_app_bar.dart';
import 'package:fav/core/widgets/section_header.dart';
import 'package:fav/features/settings/application/preferences_controller.dart';
import 'package:fav/features/settings/domain/app_language.dart';
import 'package:fav/features/settings/domain/app_theme_mode.dart';
import 'package:fav/features/settings/domain/locale_choice.dart';
import 'package:fav/features/settings/presentation/widgets/about_section.dart';
import 'package:fav/features/settings/presentation/widgets/app_lock_section.dart';
import 'package:fav/features/settings/presentation/widgets/danger_zone_section.dart';
import 'package:fav/features/settings/presentation/widgets/diagnostic_export_section.dart';
import 'package:fav/features/settings/presentation/widgets/section_radio_card.dart';
import 'package:fav/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Label for the current locale choice: the localized "follow system" string
/// or the selected language's endonym from [appLanguages].
String _localeLabel(AppLocalizations l10n, LocaleChoice choice) {
  final code = choice.code;
  if (code == null) return l10n.settingsLocaleSystem;
  for (final language in appLanguages) {
    if (language.code == code) return language.nativeName;
  }
  return l10n.settingsLocaleSystem;
}

/// Settings tab — appearance, language, security (app lock), about,
/// diagnostic and danger zone.
class SettingsScreen extends ConsumerWidget {
  /// Creates the screen.
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final prefs = ref.watch(preferencesControllerProvider);
    final controller = ref.read(preferencesControllerProvider.notifier);
    return Scaffold(
      appBar: ResponsiveAppBar(
        title: l10n.settingsTitle,
        maxContentWidth: AppSizes.contentMaxWidth,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: AppSizes.contentMaxWidth,
          ),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.xxl,
            ),
            children: [
              SectionHeader(label: l10n.settingsAppearanceSection),
              const SizedBox(height: AppSpacing.sm),
              SectionRadioCard<AppThemeMode>(
                value: prefs.themeMode,
                onChanged: controller.setThemeMode,
                options: [
                  SectionRadioOption(
                    value: AppThemeMode.system,
                    label: l10n.settingsThemeSystem,
                  ),
                  SectionRadioOption(
                    value: AppThemeMode.light,
                    label: l10n.settingsThemeLight,
                  ),
                  SectionRadioOption(
                    value: AppThemeMode.dark,
                    label: l10n.settingsThemeDark,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              SectionHeader(label: l10n.settingsLanguageSection),
              const SizedBox(height: AppSpacing.sm),
              AppCard(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(_localeLabel(l10n, prefs.localeChoice)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push(settingsLanguageRoute),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              SectionHeader(label: l10n.settingsSecuritySection),
              const SizedBox(height: AppSpacing.sm),
              const AppLockSection(),
              const SizedBox(height: AppSpacing.lg),
              SectionHeader(label: l10n.backupSection),
              const SizedBox(height: AppSpacing.sm),
              AppCard(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.shield_outlined),
                  title: Text(l10n.backupTitle),
                  subtitle: Text(l10n.backupSettingsSubtitle),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push(settingsBackupRoute),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              SectionHeader(label: l10n.settingsAboutSection),
              const SizedBox(height: AppSpacing.sm),
              const AboutSection(),
              const SizedBox(height: AppSpacing.lg),
              SectionHeader(label: l10n.settingsDiagnosticSection),
              const SizedBox(height: AppSpacing.sm),
              const DiagnosticExportSection(),
              const SizedBox(height: AppSpacing.xl),
              SectionHeader(label: l10n.settingsDangerZoneSection),
              const SizedBox(height: AppSpacing.sm),
              const DangerZoneSection(),
            ],
          ),
        ),
      ),
    );
  }
}
