import 'package:fav/core/theme/app_dimens.dart';
import 'package:fav/features/monitoring/application/history_provider.dart';
import 'package:fav/features/monitoring/application/peer_display_labels_provider.dart';
import 'package:fav/features/monitoring/domain/peer_event.dart';
import 'package:fav/features/monitoring/presentation/history/history_format.dart';
import 'package:fav/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Peer (client) selector. This is a **global** filter: it narrows both the
/// connection chart and the event log to a single client, so the two halves
/// of the screen always agree on scope. Renders nothing when there is only
/// one peer to choose from.
class HistoryPeerFilter extends ConsumerWidget {
  /// Creates a [HistoryPeerFilter] bound to [serverId]'s filter state.
  const HistoryPeerFilter({
    required this.serverId,
    required this.availablePeers,
    super.key,
  });

  /// Server whose filter state this control updates.
  final String serverId;

  /// Distinct peer public keys observed in the unfiltered history.
  final List<String> availablePeers;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final filter = ref.watch(historyFilterProvider(serverId));
    final labels = ref.watch(peerDisplayLabelsProvider(serverId));
    final controller = ref.read(historyFilterProvider(serverId).notifier);
    final orderedPeers = sortPeersByDisplay(availablePeers, labels);

    if (orderedPeers.length <= 1) {
      return const SizedBox.shrink();
    }

    return DropdownButtonFormField<String?>(
      decoration: InputDecoration(
        labelText: l10n.historyFilterPeerLabel,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      initialValue: filter.peerPublicKey,
      items: [
        DropdownMenuItem<String?>(child: Text(l10n.historyFilterPeerAll)),
        for (final peer in orderedPeers)
          DropdownMenuItem<String?>(
            value: peer,
            child: Text(
              peerDisplayLabel(peer, labels),
              style: TextStyle(
                fontFamily: monoFamilyFor(
                  isFallback: isPubkeyFallback(peer, labels),
                ),
                fontFamilyFallback: monoFallbackFor(
                  isFallback: isPubkeyFallback(peer, labels),
                ),
              ),
            ),
          ),
      ],
      onChanged: controller.setPeer,
    );
  }
}

/// Connect/disconnect chips. These are **log-only**: the chart shows
/// sessions (spans), which are not typed events, so filtering by event type
/// applies to the event log alone. The control therefore sits with the log
/// section, not with the global filters.
class HistoryEventTypeChips extends ConsumerWidget {
  /// Creates a [HistoryEventTypeChips] bound to [serverId]'s filter state.
  const HistoryEventTypeChips({required this.serverId, super.key});

  /// Server whose filter state this control updates.
  final String serverId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final filter = ref.watch(historyFilterProvider(serverId));
    final controller = ref.read(historyFilterProvider(serverId).notifier);

    return Wrap(
      spacing: AppSpacing.sm,
      children: [
        FilterChip(
          label: Text(l10n.historyFilterConnect),
          selected: filter.eventTypes.contains(PeerEventType.connect),
          onSelected: (_) => controller.toggleEventType(PeerEventType.connect),
        ),
        FilterChip(
          label: Text(l10n.historyFilterDisconnect),
          selected: filter.eventTypes.contains(PeerEventType.disconnect),
          onSelected: (_) =>
              controller.toggleEventType(PeerEventType.disconnect),
        ),
      ],
    );
  }
}
