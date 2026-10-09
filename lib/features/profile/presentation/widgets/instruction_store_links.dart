import 'package:fav/core/theme/app_dimens.dart';
import 'package:fav/features/help/presentation/external_link.dart';
import 'package:fav/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// Official WireGuard app listing on a mobile app store.
///
/// Rendered on the "install the WireGuard app" instruction steps in place of a
/// screenshot, so the user can jump straight to the store. URLs point at the
/// official WireGuard apps published by WireGuard LLC.
enum WireguardStore {
  /// Apple App Store listing (iOS).
  appStore('https://apps.apple.com/app/wireguard/id1441195209'),

  /// Google Play listing (Android).
  playStore(
    'https://play.google.com/store/apps/details?id=com.wireguard.android',
  );

  const WireguardStore(this.url);

  /// Public store URL of the official WireGuard app.
  final String url;
}

/// Vertical stack of store-link buttons shown inside an instruction step card
/// for the "install" steps.
///
/// Each button opens the official WireGuard listing through the shared
/// confirm-then-launch flow used elsewhere in the app.
class InstructionStoreLinks extends StatelessWidget {
  /// Creates an [InstructionStoreLinks] for the given [stores].
  const InstructionStoreLinks({required this.stores, super.key});

  /// Stores to offer, rendered top to bottom in the order given.
  final List<WireguardStore> stores;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      children: [
        for (final store in stores) ...[
          if (store != stores.first) const SizedBox(height: AppSpacing.sm),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: Icon(_iconFor(store)),
              label: Text(_labelFor(store, l10n)),
              onPressed: () =>
                  confirmAndLaunchExternal(context, Uri.parse(store.url)),
            ),
          ),
        ],
      ],
    );
  }

  IconData _iconFor(WireguardStore store) => switch (store) {
    WireguardStore.appStore => Icons.apple,
    WireguardStore.playStore => Icons.android,
  };

  String _labelFor(WireguardStore store, AppLocalizations l10n) =>
      switch (store) {
        WireguardStore.appStore => l10n.instructionsInstallStoreAppStore,
        WireguardStore.playStore => l10n.instructionsInstallStorePlayStore,
      };
}
