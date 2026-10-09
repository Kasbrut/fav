import 'dart:async';

import 'package:fav/core/errors/app_exception.dart';
import 'package:fav/features/help/application/recent_errors_provider.dart';
import 'package:fav/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Records [code] into the recent-errors buffer and pushes the matching
/// troubleshooting card. Use from `SnackBarAction.onPressed` or inline
/// "More info" buttons.
void pushErrorHelp(BuildContext context, WidgetRef ref, ErrorCode code) {
  ref.read(recentErrorsProvider.notifier).record(code);
  unawaited(context.push('/help/errors/${code.id}'));
}

/// Builds a [SnackBarAction] labelled "Help" that opens the troubleshooting
/// card for [code]. Use as the `action:` of a `SnackBar` that surfaces an
/// error. Requires a `WidgetRef` (caller is typically a `ConsumerWidget`
/// or has access via `Consumer`).
SnackBarAction errorHelpSnackBarAction(
  BuildContext context,
  WidgetRef ref,
  ErrorCode code,
) {
  final l10n = AppLocalizations.of(context)!;
  return SnackBarAction(
    label: l10n.helpSnackBarAction,
    onPressed: () => pushErrorHelp(context, ref, code),
  );
}

/// Inline button shown under an error message block, deep-linking to the
/// troubleshooting card for [code].
class ErrorHelpButton extends ConsumerWidget {
  /// Creates the help button.
  const ErrorHelpButton({required this.code, super.key});

  /// The error code to deep-link to.
  final ErrorCode code;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    return TextButton.icon(
      onPressed: () => pushErrorHelp(context, ref, code),
      icon: const Icon(Icons.info_outline, size: 18),
      label: Text(l10n.helpMoreInfoButton),
    );
  }
}
