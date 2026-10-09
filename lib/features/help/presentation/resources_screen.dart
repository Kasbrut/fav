import 'package:fav/features/help/presentation/widgets/help_markdown_screen.dart';
import 'package:fav/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// Resources screen — renders `resources.<locale>.md` from the bundled
/// `lib/assets/help/resources/` directory. External links go through a
/// confirmation dialog; `glossary://` links navigate inside Help.
class ResourcesScreen extends StatelessWidget {
  /// Creates the screen.
  const ResourcesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return HelpMarkdownScreen(
      title: l10n.helpResourcesTitle,
      assetStem: 'resources/resources',
    );
  }
}
