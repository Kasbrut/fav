import 'package:fav/core/theme/app_dimens.dart';
import 'package:fav/core/widgets/app_banner.dart';
import 'package:fav/core/widgets/app_card.dart';
import 'package:fav/features/servers/domain/wireguard_installation.dart';
import 'package:fav/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// Separates the state FAV verified from export and client-side declarations.
class Ipv6ProfileStatus extends StatelessWidget {
  /// Creates the status summary for a v2 profile.
  const Ipv6ProfileStatus({
    required this.network,
    required this.profileExported,
    required this.clientImportDeclared,
    super.key,
  });

  /// Authoritative server-side network result.
  final NetworkConfiguration? network;

  /// Whether this screen completed a copy, share or save operation.
  final bool profileExported;

  /// Whether the user returned from the instructions declaring an import.
  final bool clientImportDeclared;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final mode = network?.ipv6Mode;
    final routed = mode == Ipv6Mode.routed;
    final modeKnown = routed || mode == Ipv6Mode.blocked;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppBanner(
          key: const Key('ipv6-mode-banner'),
          title: routed
              ? l10n.ipv6StatusRoutedTitle
              : mode == Ipv6Mode.blocked
              ? l10n.ipv6StatusBlockedTitle
              : l10n.ipv6StatusUnavailableTitle,
          message: routed
              ? l10n.ipv6StatusRoutedBody
              : mode == Ipv6Mode.blocked
              ? l10n.ipv6StatusBlockedBody
              : l10n.ipv6StatusUnavailableBody,
          variant: routed ? AppBannerVariant.success : AppBannerVariant.warning,
          icon: routed
              ? Icons.language
              : mode == Ipv6Mode.blocked
              ? Icons.block
              : Icons.error_outline,
        ),
        const SizedBox(height: AppSpacing.sm),
        AppCard(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _EvidenceRow(
                icon: modeKnown ? Icons.verified_outlined : Icons.error_outline,
                label: modeKnown
                    ? l10n.ipv6EvidenceServerVerified
                    : l10n.ipv6EvidenceServerUnavailable,
              ),
              const SizedBox(height: AppSpacing.sm),
              _EvidenceRow(
                icon: profileExported
                    ? Icons.ios_share_outlined
                    : Icons.description_outlined,
                label: profileExported
                    ? l10n.ipv6EvidenceProfileExported
                    : l10n.ipv6EvidenceProfileReady,
              ),
              const SizedBox(height: AppSpacing.sm),
              _EvidenceRow(
                icon: clientImportDeclared
                    ? Icons.person_outline
                    : Icons.phonelink_erase_outlined,
                label: clientImportDeclared
                    ? l10n.ipv6EvidenceImportDeclared
                    : l10n.ipv6EvidenceImportUnknown,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        AppBanner(
          key: const Key('ipv6-client-warning'),
          title: l10n.ipv6ClientWarningTitle,
          message: l10n.ipv6ClientWarningBody,
          variant: AppBannerVariant.warning,
          icon: Icons.shield_outlined,
        ),
      ],
    );
  }
}

class _EvidenceRow extends StatelessWidget {
  const _EvidenceRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: Text(label)),
      ],
    );
  }
}
