import 'dart:async';

import 'package:fav/core/theme/app_dimens.dart';
import 'package:fav/core/widgets/app_card.dart';
import 'package:fav/features/settings/application/preferences_controller.dart';
import 'package:fav/features/settings/data/device_auth_service.dart';
import 'package:fav/features/settings/domain/app_lock_timeout.dart';
import 'package:fav/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Security section — the app-lock switch.
///
/// Enabled only while the device reports an unlock method. Flipping the
/// switch in either direction first runs the system prompt: enabling proves
/// the prompt works, disabling cannot be done by whoever grabs the phone
/// with the app open (spec: app-lock design, decision 3).
class AppLockSection extends ConsumerWidget {
  /// Creates the section.
  const AppLockSection({super.key});

  Future<void> _toggle(
    WidgetRef ref,
    AppLocalizations l10n, {
    required bool enabled,
  }) async {
    // Capture before the first await: the gate's privacy shield covers the
    // UI while the system prompt is up, and a `ref` used after this widget
    // unmounts throws — which would make disabling the lock impossible.
    final auth = ref.read(deviceAuthServiceProvider);
    final preferences = ref.read(preferencesControllerProvider.notifier);
    final outcome = await auth.authenticate(l10n.appLockReason);
    // Turning the lock OFF is also allowed when the device no longer has
    // any unlock enrolled (fail open); turning it ON never is.
    final allowed =
        outcome == DeviceAuthOutcome.passed ||
        (!enabled && outcome == DeviceAuthOutcome.noCredentials);
    if (!allowed) return;
    await preferences.setAppLockEnabled(enabled: enabled);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final enabled = ref.watch(
      preferencesControllerProvider.select((p) => p.appLockEnabled),
    );
    final available = ref.watch(deviceAuthAvailableProvider).value ?? false;
    final timeout = ref.watch(
      preferencesControllerProvider.select((p) => p.appLockTimeout),
    );
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.settingsAppLockTitle),
            subtitle: Text(
              available
                  ? l10n.settingsAppLockSubtitle
                  : l10n.settingsAppLockUnavailable,
            ),
            value: enabled,
            onChanged: available
                ? (value) => unawaited(_toggle(ref, l10n, enabled: value))
                : null,
          ),
          if (enabled) ...[
            const Divider(),
            const SizedBox(height: AppSpacing.sm),
            Text(
              l10n.settingsAppLockTimeoutTitle,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              l10n.settingsAppLockTimeoutSubtitle,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            DropdownButtonFormField<AppLockTimeout>(
              initialValue: timeout,
              items: AppLockTimeout.values
                  .map(
                    (option) => DropdownMenuItem(
                      value: option,
                      child: Text(_timeoutLabel(l10n, option)),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  unawaited(
                    ref
                        .read(preferencesControllerProvider.notifier)
                        .setAppLockTimeout(value),
                  );
                }
              },
            ),
            const SizedBox(height: AppSpacing.md),
          ],
        ],
      ),
    );
  }

  String _timeoutLabel(AppLocalizations l10n, AppLockTimeout timeout) {
    return switch (timeout) {
      AppLockTimeout.oneMinute => l10n.settingsAppLockTimeout1m,
      AppLockTimeout.twoMinutes => l10n.settingsAppLockTimeout2m,
      AppLockTimeout.fiveMinutes => l10n.settingsAppLockTimeout5m,
      AppLockTimeout.onlyOnLaunch => l10n.settingsAppLockTimeoutLaunch,
    };
  }
}
