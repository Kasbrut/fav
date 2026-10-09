import 'dart:async';

import 'package:fav/core/theme/app_dimens.dart';
import 'package:fav/core/theme/app_semantic_colors.dart';
import 'package:fav/features/monitoring/application/peer_display_labels_provider.dart';
import 'package:fav/features/monitoring/domain/connection_session.dart';
import 'package:fav/features/monitoring/presentation/history/history_format.dart';
import 'package:fav/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

const double _trackHeight = 30;
const double _rowGap = AppSpacing.md;
const double _axisHeight = 22;
const double _barRadius = 4;

/// A horizontal Gantt-style timeline of connection sessions, one block per
/// peer. The peer's name sits on its own line above a full-width track, so
/// the bars use the whole screen width (important on narrow phones). The
/// name shows the display label, or a short pubkey when the peer is not in
/// the local peers store; a trailing summary shows total connected time.
class ConnectionTimelineChart extends ConsumerWidget {
  /// Creates a [ConnectionTimelineChart].
  const ConnectionTimelineChart({
    required this.serverId,
    required this.sessions,
    required this.windowStart,
    required this.windowEnd,
    super.key,
  });

  /// Server whose peer labels we resolve for display.
  final String serverId;

  /// Sessions clipped to the window — see `serverHistoryProvider`.
  final List<ConnectionSession> sessions;

  /// Inclusive start of the visible window.
  final DateTime windowStart;

  /// Exclusive end of the visible window.
  final DateTime windowEnd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final labels = ref.watch(peerDisplayLabelsProvider(serverId));
    final peers = sortPeersByDisplay(
      <String>{for (final s in sessions) s.peerPublicKey},
      labels,
    );
    final byPeer = <String, List<ConnectionSession>>{
      for (final peer in peers) peer: [],
    };
    for (final session in sessions) {
      byPeer[session.peerPublicKey]!.add(session);
    }

    if (peers.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Text(
          l10n.historyChartEmpty,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    final totalSpanMs = windowEnd.difference(windowStart).inMilliseconds;
    if (totalSpanMs <= 0) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final chartWidth = constraints.maxWidth;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _ChartLegend(),
            const SizedBox(height: AppSpacing.md),
            for (var i = 0; i < peers.length; i++) ...[
              _PeerRow(
                peer: peers[i],
                displayLabel: peerDisplayLabel(peers[i], labels),
                isFallbackLabel: isPubkeyFallback(peers[i], labels),
                summary: formatDuration(
                  l10n,
                  byPeer[peers[i]]!.fold<Duration>(
                    Duration.zero,
                    (total, s) => total + s.durationUntil(windowEnd),
                  ),
                ),
                serverId: serverId,
                sessions: byPeer[peers[i]]!,
                chartWidth: chartWidth,
                windowStart: windowStart,
                totalSpanMs: totalSpanMs,
              ),
              if (i != peers.length - 1) const SizedBox(height: _rowGap),
            ],
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              height: _axisHeight,
              child: _AxisLabels(
                windowStart: windowStart,
                windowEnd: windowEnd,
                chartWidth: chartWidth,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// A compact legend explaining the bar colours and the RX/TX shorthand, so a
/// first-time viewer knows what the timeline is showing.
class _ChartLegend extends StatelessWidget {
  const _ChartLegend();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final success = context.semantic.success;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.xs,
          children: [
            _LegendItem(
              color: success,
              label: l10n.historyEventConnect,
              style: muted,
            ),
            _LegendItem(
              color: success.withValues(alpha: 0.65),
              bordered: true,
              label: l10n.historySessionInProgress,
              style: muted,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(l10n.historyLegendBytes, style: muted),
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({
    required this.color,
    required this.label,
    this.bordered = false,
    this.style,
  });

  final Color color;
  final String label;
  final bool bordered;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
            border: bordered
                ? Border.all(color: Theme.of(context).colorScheme.onSurface)
                : null,
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Text(label, style: style),
      ],
    );
  }
}

class _PeerRow extends StatelessWidget {
  const _PeerRow({
    required this.peer,
    required this.displayLabel,
    required this.isFallbackLabel,
    required this.summary,
    required this.serverId,
    required this.sessions,
    required this.chartWidth,
    required this.windowStart,
    required this.totalSpanMs,
  });

  final String peer;
  final String displayLabel;
  final bool isFallbackLabel;
  final String summary;
  final String serverId;
  final List<ConnectionSession> sessions;
  final double chartWidth;
  final DateTime windowStart;
  final int totalSpanMs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.xs),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  displayLabel,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: monoFamilyFor(isFallback: isFallbackLabel),
                    fontFamilyFallback: monoFallbackFor(
                      isFallback: isFallbackLabel,
                    ),
                    color: theme.colorScheme.onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                summary,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: _trackHeight,
          child: Stack(
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(_barRadius),
                  ),
                ),
              ),
              for (final session in sessions)
                _SessionBar(
                  session: session,
                  displayLabel: displayLabel,
                  serverId: serverId,
                  chartWidth: chartWidth,
                  windowStart: windowStart,
                  totalSpanMs: totalSpanMs,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SessionBar extends StatelessWidget {
  const _SessionBar({
    required this.session,
    required this.displayLabel,
    required this.serverId,
    required this.chartWidth,
    required this.windowStart,
    required this.totalSpanMs,
  });

  final ConnectionSession session;
  final String displayLabel;
  final String serverId;
  final double chartWidth;
  final DateTime windowStart;
  final int totalSpanMs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final windowEnd = windowStart.add(Duration(milliseconds: totalSpanMs));
    final fmt = DateFormat.MMMd().add_Hm();
    final endText = session.end == null
        ? l10n.historySessionInProgress
        : fmt.format(session.end!.toLocal());
    final semanticLabel = l10n.historySessionSemantic(
      displayLabel,
      fmt.format(session.start.toLocal()),
      endText,
      formatDuration(l10n, session.durationUntil(windowEnd)),
    );
    final startMs = session.start
        .difference(windowStart)
        .inMilliseconds
        .clamp(0, totalSpanMs);
    final effectiveEnd =
        session.end ?? windowStart.add(Duration(milliseconds: totalSpanMs));
    final endMs = effectiveEnd
        .difference(windowStart)
        .inMilliseconds
        .clamp(startMs, totalSpanMs);
    final left = chartWidth * (startMs / totalSpanMs);
    final width = (chartWidth * ((endMs - startMs) / totalSpanMs)).clamp(
      2.0,
      chartWidth,
    );
    final color = session.isOpen
        ? context.semantic.success.withValues(alpha: 0.65)
        : context.semantic.success;
    return Positioned(
      left: left,
      width: width,
      top: 0,
      bottom: 0,
      child: Semantics(
        button: true,
        label: semanticLabel,
        child: GestureDetector(
          onTap: () => _showSessionSheet(context, session, serverId),
          child: Container(
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(_barRadius),
              border: session.isOpen
                  ? Border.all(color: theme.colorScheme.onSurface)
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}

void _showSessionSheet(
  BuildContext context,
  ConnectionSession session,
  String serverId,
) {
  unawaited(
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => Consumer(
        builder: (context, ref, _) {
          final l10n = AppLocalizations.of(context)!;
          final labels = ref.watch(peerDisplayLabelsProvider(serverId));
          final displayLabel = peerDisplayLabel(session.peerPublicKey, labels);
          final fallback = isPubkeyFallback(session.peerPublicKey, labels);
          final now = DateTime.now().toUtc();
          final duration = session.durationUntil(now);
          final theme = Theme.of(context);
          final fmt = DateFormat.yMMMd().add_Hms();
          return Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.xl,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayLabel,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontFamily: monoFamilyFor(isFallback: fallback),
                    fontFamilyFallback: monoFallbackFor(isFallback: fallback),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                _SheetRow(
                  label: l10n.historySessionStartLabel,
                  value: fmt.format(session.start.toLocal()),
                ),
                _SheetRow(
                  label: l10n.historySessionEndLabel,
                  value: session.end == null
                      ? l10n.historySessionInProgress
                      : fmt.format(session.end!.toLocal()),
                ),
                _SheetRow(
                  label: l10n.historySessionDurationLabel,
                  value: formatDuration(l10n, duration),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  l10n.historyBytesPair(
                    formatBytes(session.rxBytes),
                    formatBytes(session.txBytes),
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    ),
  );
}

class _SheetRow extends StatelessWidget {
  const _SheetRow({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

class _AxisLabels extends StatelessWidget {
  const _AxisLabels({
    required this.windowStart,
    required this.windowEnd,
    required this.chartWidth,
  });

  final DateTime windowStart;
  final DateTime windowEnd;
  final double chartWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final spansDay = windowEnd.difference(windowStart).inHours >= 24;
    final fmt = spansDay ? DateFormat.Md() : DateFormat.Hm();
    final mid = DateTime.fromMillisecondsSinceEpoch(
      (windowStart.millisecondsSinceEpoch + windowEnd.millisecondsSinceEpoch) ~/
          2,
      isUtc: true,
    );
    final style = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: SizedBox(
        width: chartWidth,
        child: Stack(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(fmt.format(windowStart.toLocal()), style: style),
            ),
            Align(child: Text(fmt.format(mid.toLocal()), style: style)),
            Align(
              alignment: Alignment.centerRight,
              child: Text(fmt.format(windowEnd.toLocal()), style: style),
            ),
          ],
        ),
      ),
    );
  }
}
