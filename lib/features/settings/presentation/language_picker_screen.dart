import 'package:fav/core/theme/app_dimens.dart';
import 'package:fav/core/widgets/responsive_app_bar.dart';
import 'package:fav/core/widgets/responsive_content.dart';
import 'package:fav/features/settings/application/preferences_controller.dart';
import 'package:fav/features/settings/domain/app_language.dart';
import 'package:fav/features/settings/domain/locale_choice.dart';
import 'package:fav/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Full-screen language picker reached from Settings → Language.
///
/// Lists "Follow system" plus every entry in [appLanguages]; the active choice
/// is marked with a check. Selecting a row persists the locale and pops back.
/// A scrollable list scales to any number of languages and full-width rows
/// handle long endonyms.
class LanguagePickerScreen extends ConsumerWidget {
  /// Creates the screen.
  const LanguagePickerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final current = ref.watch(preferencesControllerProvider).localeChoice;
    final controller = ref.read(preferencesControllerProvider.notifier);

    Future<void> select(LocaleChoice choice) async {
      await controller.setLocale(choice);
      if (context.mounted) context.pop();
    }

    return Scaffold(
      appBar: ResponsiveAppBar(
        title: l10n.settingsLanguageSection,
        maxContentWidth: AppSizes.contentMaxWidth,
      ),
      body: ResponsiveContent(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            AppSpacing.xxl,
          ),
          children: [
            _LanguageTile(
              label: l10n.settingsLocaleSystem,
              selected: current == LocaleChoice.system,
              onTap: () => select(LocaleChoice.system),
            ),
            for (final language in appLanguages)
              _LanguageTile(
                label: language.nativeName,
                selected: current == LocaleChoice.forCode(language.code),
                onTap: () => select(LocaleChoice.forCode(language.code)),
              ),
          ],
        ),
      ),
    );
  }
}

class _LanguageTile extends StatelessWidget {
  const _LanguageTile({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(label),
      trailing: selected
          ? Icon(Icons.check, color: Theme.of(context).colorScheme.primary)
          : null,
      onTap: onTap,
    );
  }
}
