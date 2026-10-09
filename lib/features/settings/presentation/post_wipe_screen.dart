import 'dart:async';
import 'dart:io' show Platform;

import 'package:fav/core/theme/app_dimens.dart';
import 'package:fav/core/utils/app_logger.dart';
import 'package:fav/core/widgets/code_block.dart';
import 'package:fav/features/settings/application/app_reset_service.dart';
import 'package:fav/l10n/app_localizations.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Terminal screen of the wipe flow: it owns the wipe itself.
///
/// The danger zone navigates here *before* any box closes (audit M11), so no
/// other screen is mounted while local data disappears underneath it. On
/// Android a successful wipe exits the app; on iOS (where
/// `SystemNavigator.pop()` is a no-op) the user is told to close it from the
/// task switcher. A failed wipe shows the reason but stays terminal — the
/// data is half-deleted, so restarting the app is the only way on. No back
/// action either way.
class PostWipeScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const PostWipeScreen({super.key});

  @override
  ConsumerState<PostWipeScreen> createState() => _PostWipeScreenState();
}

class _PostWipeScreenState extends ConsumerState<PostWipeScreen> {
  late Future<void> _wipe;

  @override
  void initState() {
    super.initState();
    _startWipe();
  }

  void _startWipe() {
    _wipe = ref.read(appResetServiceProvider).wipe();
    unawaited(
      _wipe.then(
        (_) {
          if (!kIsWeb && Platform.isAndroid) {
            unawaited(SystemNavigator.pop());
          }
        },
        // The error is rendered by the FutureBuilder below; this handler
        // only keeps the future from surfacing as uncaught.
        onError: (Object _) {},
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: FutureBuilder<void>(
            future: _wipe,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              final error = snapshot.error;
              if (error != null) {
                return _FailureView(
                  error: error,
                  l10n: l10n,
                  onRetry: () => setState(_startWipe),
                );
              }
              // Center, not bare Padding: the Scaffold body hands out loose
              // width constraints, so the column shrink-wraps its widest
              // child and would anchor top-left (device test 2026-08-19).
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.check_circle_outline,
                        size: 64,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      Text(
                        l10n.settingsPostWipeTitle,
                        style: theme.textTheme.headlineSmall,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        l10n.settingsPostWipeBody,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Failure outcome of the wipe: says honestly that data may remain and
/// offers a retry (security audit H3). Scrollable — a platform exception
/// can carry a full native stack trace (audit M2) — with the technical
/// reason routed through the secret redactor as a defense-in-depth net.
class _FailureView extends StatelessWidget {
  const _FailureView({
    required this.error,
    required this.l10n,
    required this.onRetry,
  });

  final Object error;
  final AppLocalizations l10n;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        Icon(Icons.error_outline, size: 64, color: theme.colorScheme.error),
        const SizedBox(height: AppSpacing.lg),
        Text(
          l10n.settingsWipeFailedTitle,
          style: theme.textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.md),
        Text(l10n.settingsWipeFailedBody, textAlign: TextAlign.center),
        const SizedBox(height: AppSpacing.lg),
        CodeBlock(content: redactSecrets(error.toString())),
        const SizedBox(height: AppSpacing.xl),
        FilledButton(onPressed: onRetry, child: Text(l10n.actionRetry)),
      ],
    );
  }
}
