import 'package:fav/core/theme/app_dimens.dart';
import 'package:fav/core/widgets/empty_state.dart';
import 'package:fav/core/widgets/section_header.dart';
import 'package:fav/features/monitoring/application/history_provider.dart';
import 'package:fav/features/monitoring/application/monitor_polling_controller.dart';
import 'package:fav/features/monitoring/domain/client_live_status.dart';
import 'package:fav/features/monitoring/presentation/history/connection_timeline_chart.dart';
import 'package:fav/features/monitoring/presentation/history/event_log_table.dart';
import 'package:fav/features/monitoring/presentation/history/history_filter_bar.dart';
import 'package:fav/features/monitoring/presentation/history/history_range_chips.dart';
import 'package:fav/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Per-server connection history: timeline chart + filterable log table.
///
/// Reads from the locally-persisted `monitoring_events` Hive box; no new
/// SSH traffic is initiated by this screen. Polling for fresh data is the
/// responsibility of `MonitorPollingController`, which the
/// `peerEventsProvider` keeps watching so the screen refreshes whenever
/// new events land.
class ServerHistoryScreen extends ConsumerWidget {
  /// Creates the history screen for the server identified by [serverId].
  const ServerHistoryScreen({required this.serverId, super.key});

  /// Identifier of the server to show.
  final String serverId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final history = ref.watch(serverHistoryProvider(serverId));
    // No events at all: tell the user why. A missing monitoring agent looks
    // identical to a quiet server otherwise.
    if (history.peers.isEmpty) {
      final polling = ref.watch(monitorPollingControllerProvider(serverId));
      final agentMissing =
          polling.lastErrorReason == ClientLiveStatusUnknownReason.notInstalled;
      return Scaffold(
        appBar: AppBar(title: Text(l10n.historyTitle)),
        body: EmptyState(
          icon: agentMissing ? Icons.monitor_heart_outlined : Icons.timeline,
          title: agentMissing
              ? l10n.historyMonitorMissingTitle
              : l10n.historyEmptyTitle,
          message: agentMissing
              ? l10n.historyMonitorMissingBody
              : l10n.historyEmptyBody,
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(l10n.historyTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.xxl,
        ),
        children: [
          // Global controls: window + client. The client filter narrows both
          // the chart and the log, so it lives here, above both sections.
          HistoryRangeChips(serverId: serverId),
          if (history.peers.length > 1) ...[
            const SizedBox(height: AppSpacing.md),
            HistoryPeerFilter(
              serverId: serverId,
              availablePeers: history.peers,
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          SectionHeader(label: l10n.historySectionChart),
          const SizedBox(height: AppSpacing.sm),
          ConnectionTimelineChart(
            serverId: serverId,
            sessions: history.sessions,
            windowStart: history.windowStart,
            windowEnd: history.windowEnd,
          ),
          const SizedBox(height: AppSpacing.lg),
          SectionHeader(label: l10n.historySectionLog),
          const SizedBox(height: AppSpacing.sm),
          // Event-type chips are scoped to the log only (sessions are spans,
          // not typed events), so they sit with the log, not the chart.
          HistoryEventTypeChips(serverId: serverId),
          const SizedBox(height: AppSpacing.sm),
          EventLogTable(serverId: serverId, events: history.filteredEvents),
        ],
      ),
    );
  }
}
