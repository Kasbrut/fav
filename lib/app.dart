import 'dart:async';

import 'package:fav/core/router/app_router.dart';
import 'package:fav/core/theme/app_dimens.dart';
import 'package:fav/core/theme/app_theme.dart';
import 'package:fav/core/utils/app_logger.dart';
import 'package:fav/core/widgets/code_block.dart';
import 'package:fav/features/settings/application/app_reset_service.dart';
import 'package:fav/features/settings/application/locale_override_provider.dart';
import 'package:fav/features/settings/application/preference_mappers.dart';
import 'package:fav/features/settings/application/theme_mode_provider.dart';
import 'package:fav/features/settings/presentation/app_lock_gate.dart';
import 'package:fav/features/settings/presentation/post_wipe_screen.dart';
import 'package:fav/features/settings/presentation/widgets/wipe_confirmation_dialogs.dart';
import 'package:fav/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Root widget of the FAV application.
class WireguardProvisionerApp extends ConsumerWidget {
  /// Creates the root application widget.
  const WireguardProvisionerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeModeProvider);
    final localeOverride = ref.watch(localeOverrideProvider);
    return MaterialApp.router(
      onGenerateTitle: (context) => AppLocalizations.of(context)!.appTitle,
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: themeMode.toMaterial(),
      locale: localeOverride,
      routerConfig: router,
      builder: (context, child) =>
          AppLockGate(child: child ?? const SizedBox.shrink()),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
    );
  }
}

/// Minimal fallback app for a failed boot sequence (audit M10): the
/// encrypted database or the startup migration threw before `runApp`, e.g.
/// after an OS backup restore left Hive files that no longer match the
/// keystore key. Touches no box-backed provider — only theme + l10n — and
/// offers the standard wipe (same confirmation flow and terminal screen as
/// the Settings danger zone) as the recovery path.
class BootFailureApp extends StatelessWidget {
  /// Creates the fallback app for [error].
  const BootFailureApp({required this.error, super.key, this.resetService});

  /// The error thrown by the boot sequence.
  final Object error;

  /// Test override for the reset service; production uses the provider's
  /// default (real Hive + secure storage deletion).
  final AppResetService? resetService;

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: [
        if (resetService != null)
          appResetServiceProvider.overrideWithValue(resetService!),
      ],
      child: MaterialApp(
        onGenerateTitle: (context) => AppLocalizations.of(context)!.appTitle,
        theme: lightTheme,
        darkTheme: darkTheme,
        // No `locale:` — the in-app language override lives in the
        // preferences box, which is exactly what failed to open. The whole
        // flow (confirm word included) follows the OS locale here; an
        // accepted limitation of the recovery path (security audit L2).
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: _BootFailureScreen(error: error),
      ),
    );
  }
}

class _BootFailureScreen extends StatelessWidget {
  const _BootFailureScreen({required this.error});

  final Object error;

  Future<void> _onErase(BuildContext context) async {
    final confirmed = await WipeConfirmationFlow.show(context);
    if (!confirmed || !context.mounted) return;
    // The terminal screen owns the wipe and its outcome; replace the stack
    // so there is no way back into the broken app.
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const PostWipeScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          children: [
            const SizedBox(height: AppSpacing.xl),
            Icon(
              Icons.error_outline,
              size: 64,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              l10n.bootFailureTitle,
              style: theme.textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(l10n.bootFailureBody, textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.lg),
            // Second net behind the scrubbed throw sites (audit H2): the
            // detail is selectable and ends up pasted into bug reports.
            CodeBlock(content: redactSecrets(error.toString())),
            const SizedBox(height: AppSpacing.xl),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.error,
                foregroundColor: theme.colorScheme.onError,
              ),
              icon: const Icon(Icons.delete_forever),
              label: Text(l10n.settingsWipeButton),
              onPressed: () => unawaited(_onErase(context)),
            ),
          ],
        ),
      ),
    );
  }
}
