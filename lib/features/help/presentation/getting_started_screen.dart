import 'package:fav/features/help/presentation/widgets/help_markdown_screen.dart';
import 'package:fav/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// Getting-started guide — renders `getting_started.<locale>.md` from the
/// bundled `lib/assets/help/getting_started/` directory. External links go
/// through a confirmation dialog; `glossary://` links navigate inside Help.
class GettingStartedScreen extends StatelessWidget {
  /// Creates the screen.
  const GettingStartedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return HelpMarkdownScreen(
      title: l10n.helpGettingStartedTitle,
      assetStem: 'getting_started/getting_started',
    );
  }
}
