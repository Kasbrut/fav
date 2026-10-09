import 'package:fav/features/help/presentation/widgets/help_markdown_screen.dart';
import 'package:fav/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// FAQ screen — renders `faq.<locale>.md` from the bundled
/// `lib/assets/help/faq/` directory. External links go through a
/// confirmation dialog; `glossary://` links navigate inside Help.
class FaqScreen extends StatelessWidget {
  /// Creates the screen.
  const FaqScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return HelpMarkdownScreen(title: l10n.helpFaqTitle, assetStem: 'faq/faq');
  }
}
