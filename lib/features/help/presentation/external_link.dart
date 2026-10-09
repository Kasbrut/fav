import 'package:fav/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Shows a confirmation dialog before launching [uri] in the default
/// browser. Used by Help markdown screens and the Settings About section.
Future<void> confirmAndLaunchExternal(BuildContext context, Uri uri) async {
  final l10n = AppLocalizations.of(context)!;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l10n.helpExternalLinkConfirmTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.helpExternalLinkConfirmBody),
          const SizedBox(height: 8),
          SelectableText(uri.toString()),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(l10n.helpExternalLinkConfirmCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(l10n.helpExternalLinkConfirmContinue),
        ),
      ],
    ),
  );
  if (ok ?? false) {
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } on Object {
      // Silent failure — callers like Help screens currently don't
      // surface this. The Settings flow is symmetric.
    }
  }
}
