import 'package:fav/features/help/presentation/widgets/help_markdown_screen.dart';
import 'package:fav/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// Donate screen — renders `donate.<locale>.md` from the bundled
/// `lib/assets/help/donate/` directory. External links go through a
/// confirmation dialog.
class DonateScreen extends StatelessWidget {
  /// Creates the screen.
  const DonateScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return HelpMarkdownScreen(
      title: l10n.helpDonateTitle,
      assetStem: 'donate/donate',
    );
  }
}
