import 'package:fav/core/theme/app_dimens.dart';
import 'package:fav/core/widgets/app_card.dart';
import 'package:fav/core/widgets/responsive_app_bar.dart';
import 'package:fav/core/widgets/responsive_content.dart';
import 'package:fav/features/help/domain/glossary_entries.dart';
import 'package:fav/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// Renders the 14-entry glossary. When [term] matches an entry's slug, the
/// list scrolls to that card on first frame.
class GlossaryScreen extends StatefulWidget {
  /// Creates the screen.
  const GlossaryScreen({this.term, super.key});

  /// Optional slug to scroll to (deep-link target).
  final String? term;

  @override
  State<GlossaryScreen> createState() => _GlossaryScreenState();
}

class _GlossaryScreenState extends State<GlossaryScreen> {
  final Map<String, GlobalKey> _keys = {
    for (final e in glossaryEntries) e.slug: GlobalKey(),
  };

  @override
  void initState() {
    super.initState();
    final t = widget.term;
    if (t != null && _keys.containsKey(t)) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final ctx = _keys[t]!.currentContext;
        if (ctx != null) {
          await Scrollable.ensureVisible(
            ctx,
            duration: const Duration(milliseconds: 300),
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: ResponsiveAppBar(
        title: l10n.helpGlossaryTitle,
        maxContentWidth: AppSizes.contentMaxWidth,
      ),
      body: ResponsiveContent(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.xxl,
          ),
          children: [
            for (final entry in glossaryEntries) ...[
              AppCard(
                key: _keys[entry.slug],
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _lookup(l10n, entry.titleKey),
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(_lookup(l10n, entry.bodyKey)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
          ],
        ),
      ),
    );
  }

  /// Maps a known ARB key name to its localized string.
  ///
  /// Since [AppLocalizations] is code-generated and has no reflection, we
  /// hand-roll a switch covering the 28 glossary keys. The
  /// `glossary_arb_keys_test.dart` test catches any drift between this switch
  /// and the [glossaryEntries] registry.
  String _lookup(AppLocalizations l10n, String key) {
    switch (key) {
      case 'glossaryAllowedIpsTitle':
        return l10n.glossaryAllowedIpsTitle;
      case 'glossaryAllowedIpsBody':
        return l10n.glossaryAllowedIpsBody;
      case 'glossaryDnsTitle':
        return l10n.glossaryDnsTitle;
      case 'glossaryDnsBody':
        return l10n.glossaryDnsBody;
      case 'glossaryFingerprintTitle':
        return l10n.glossaryFingerprintTitle;
      case 'glossaryFingerprintBody':
        return l10n.glossaryFingerprintBody;
      case 'glossaryFirewallTitle':
        return l10n.glossaryFirewallTitle;
      case 'glossaryFirewallBody':
        return l10n.glossaryFirewallBody;
      case 'glossaryHardeningTitle':
        return l10n.glossaryHardeningTitle;
      case 'glossaryHardeningBody':
        return l10n.glossaryHardeningBody;
      case 'glossaryHandshakeTitle':
        return l10n.glossaryHandshakeTitle;
      case 'glossaryHandshakeBody':
        return l10n.glossaryHandshakeBody;
      case 'glossaryMtuTitle':
        return l10n.glossaryMtuTitle;
      case 'glossaryMtuBody':
        return l10n.glossaryMtuBody;
      case 'glossaryPeerTitle':
        return l10n.glossaryPeerTitle;
      case 'glossaryPeerBody':
        return l10n.glossaryPeerBody;
      case 'glossaryPublicPrivateKeyTitle':
        return l10n.glossaryPublicPrivateKeyTitle;
      case 'glossaryPublicPrivateKeyBody':
        return l10n.glossaryPublicPrivateKeyBody;
      case 'glossarySshTitle':
        return l10n.glossarySshTitle;
      case 'glossarySshBody':
        return l10n.glossarySshBody;
      case 'glossarySubnetTitle':
        return l10n.glossarySubnetTitle;
      case 'glossarySubnetBody':
        return l10n.glossarySubnetBody;
      case 'glossarySudoTitle':
        return l10n.glossarySudoTitle;
      case 'glossarySudoBody':
        return l10n.glossarySudoBody;
      case 'glossaryUdpPortTitle':
        return l10n.glossaryUdpPortTitle;
      case 'glossaryUdpPortBody':
        return l10n.glossaryUdpPortBody;
      case 'glossaryVpnTitle':
        return l10n.glossaryVpnTitle;
      case 'glossaryVpnBody':
        return l10n.glossaryVpnBody;
      case 'glossaryWireguardTitle':
        return l10n.glossaryWireguardTitle;
      case 'glossaryWireguardBody':
        return l10n.glossaryWireguardBody;
    }
    return key;
  }
}
