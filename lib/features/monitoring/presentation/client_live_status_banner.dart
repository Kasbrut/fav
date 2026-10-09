import 'package:fav/core/widgets/app_banner.dart';
import 'package:fav/features/monitoring/application/client_live_status_provider.dart';
import 'package:fav/features/monitoring/domain/client_live_status.dart';
import 'package:fav/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Live banner showing the connection state of a specific client peer
/// (M15-T6). Replaces the static "VPN active" banner in `ProfileResultScreen`.
class ClientLiveStatusBanner extends ConsumerWidget {
  /// Creates a [ClientLiveStatusBanner].
  const ClientLiveStatusBanner({
    required this.serverId,
    required this.clientPublicKey,
    super.key,
  });

  /// Identifier of the server the peer belongs to.
  final String serverId;

  /// Canonical-base64 public key of the peer.
  final String clientPublicKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final status = ref.watch(
      clientLiveStatusProvider(
        ClientLiveStatusKey(
          serverId: serverId,
          peerPublicKey: clientPublicKey,
        ),
      ),
    );
    final (AppBannerVariant variant, IconData icon, String message) =
        _stylesFor(status, l10n);
    return AppBanner(variant: variant, icon: icon, message: message);
  }

  (AppBannerVariant, IconData, String) _stylesFor(
    ClientLiveStatus status,
    AppLocalizations l10n,
  ) {
    return switch (status) {
      ClientLiveStatusConnected() => (
        AppBannerVariant.success,
        Icons.check_circle,
        l10n.monitorBannerConnected,
      ),
      ClientLiveStatusLastSeen(:final serverTimestamp) => (
        AppBannerVariant.info,
        Icons.schedule,
        '${l10n.monitorBannerLastSeenPrefix}'
            '${_formatTimeAgo(l10n, serverTimestamp)}',
      ),
      ClientLiveStatusNeverConnected() => (
        AppBannerVariant.warning,
        Icons.vpn_key_off,
        l10n.monitorBannerNeverConnected,
      ),
      ClientLiveStatusUnknown(:final reason) => switch (reason) {
        ClientLiveStatusUnknownReason.agentStale => (
          AppBannerVariant.warning,
          Icons.sync_problem,
          l10n.monitorBannerAgentStale,
        ),
        ClientLiveStatusUnknownReason.sshDown => (
          AppBannerVariant.info,
          Icons.cloud_off,
          l10n.monitorBannerSshDown,
        ),
        ClientLiveStatusUnknownReason.notInstalled => (
          AppBannerVariant.info,
          Icons.monitor_heart_outlined,
          l10n.monitorBannerNotInstalled,
        ),
      },
    };
  }

  String _formatTimeAgo(AppLocalizations l10n, DateTime serverTimestamp) {
    final delta = DateTime.now().toUtc().difference(serverTimestamp.toUtc());
    if (delta.inMinutes < 1) {
      return l10n.lastSeenJustNow.toLowerCase();
    }
    if (delta.inHours < 1) {
      return l10n.lastSeenMinutesAgo(delta.inMinutes);
    }
    if (delta.inDays < 1) {
      return l10n.lastSeenHoursAgo(delta.inHours);
    }
    return l10n.lastSeenDaysAgo(delta.inDays);
  }
}
