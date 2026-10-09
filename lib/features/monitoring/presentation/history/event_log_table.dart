import 'dart:async';

import 'package:fav/core/theme/app_dimens.dart';
import 'package:fav/core/theme/app_semantic_colors.dart';
import 'package:fav/core/utils/relative_time.dart';
import 'package:fav/features/monitoring/application/peer_display_labels_provider.dart';
import 'package:fav/features/monitoring/domain/peer_event.dart';
import 'package:fav/features/monitoring/presentation/history/history_format.dart';
import 'package:fav/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

/// How many rows are built up front before the user expands. Bounds the
/// build cost on busy servers without hiding anything: the rest is one tap
/// away behind a "Show older events" button.
const int _initialLogLimit = 100;

/// Filterable list of [PeerEvent]s rendered as one row each, capped to the
/// most recent [_initialLogLimit] until the user asks for older ones.
class EventLogTable extends ConsumerStatefulWidget {
  /// Creates an [EventLogTable].
  const EventLogTable({
    required this.serverId,
    required this.events,
    super.key,
  });

  /// Server whose peer labels we resolve for display.
  final String serverId;

  /// Events to render, already filtered and ordered (newest first).
  final List<PeerEvent> events;

  @override
  ConsumerState<EventLogTable> createState() => _EventLogTableState();
}

class _EventLogTableState extends ConsumerState<EventLogTable> {
  bool _showAll = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final events = widget.events;
    if (events.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Text(
          l10n.historyLogEmpty,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    final labels = ref.watch(peerDisplayLabelsProvider(widget.serverId));
    final fmt = DateFormat.MMMd().add_Hms();
    final showAll = _showAll || events.length <= _initialLogLimit;
    final visible = showAll
        ? events
        : events.take(_initialLogLimit).toList(growable: false);
    return Column(
      children: [
        for (final event in visible)
          _LogRow(
            event: event,
            displayLabel: peerDisplayLabel(event.peerPublicKey, labels),
            isFallbackLabel: isPubkeyFallback(event.peerPublicKey, labels),
            l10n: l10n,
            fmt: fmt,
          ),
        if (!showAll)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => setState(() => _showAll = true),
                child: Text(
                  l10n.historyLogShowOlder(events.length - _initialLogLimit),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Bottom sheet with the full detail of a single [PeerEvent]: an always
/// reachable alternative to the timeline's tiny session bars.
void _showEventSheet(
  BuildContext context,
  PeerEvent event,
  String displayLabel,
  bool isFallbackLabel,
  AppLocalizations l10n,
) {
  final isConnect = event.type == PeerEventType.connect;
  final fmt = DateFormat.yMMMd().add_Hms();
  unawaited(
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final theme = Theme.of(context);
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
                  fontFamily: monoFamilyFor(isFallback: isFallbackLabel),
                  fontFamilyFallback: monoFallbackFor(
                    isFallback: isFallbackLabel,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              _EventSheetRow(
                label: l10n.historyFilterEventTypeLabel,
                value: isConnect
                    ? l10n.historyEventConnect
                    : l10n.historyEventDisconnect,
              ),
              _EventSheetRow(
                label: l10n.historyEventTimeLabel,
                value: fmt.format(event.serverTimestamp.toLocal()),
              ),
              if (event.rx > 0 || event.tx > 0) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  l10n.historyBytesPair(
                    formatBytes(event.rx),
                    formatBytes(event.tx),
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    ),
  );
}

class _EventSheetRow extends StatelessWidget {
  const _EventSheetRow({required this.label, required this.value});
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

class _LogRow extends StatelessWidget {
  const _LogRow({
    required this.event,
    required this.displayLabel,
    required this.isFallbackLabel,
    required this.l10n,
    required this.fmt,
  });

  final PeerEvent event;
  final String displayLabel;
  final bool isFallbackLabel;
  final AppLocalizations l10n;
  final DateFormat fmt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isConnect = event.type == PeerEventType.connect;
    final color = isConnect
        ? context.semantic.success
        : theme.colorScheme.onSurfaceVariant;
    return InkWell(
      onTap: () =>
          _showEventSheet(context, event, displayLabel, isFallbackLabel, l10n),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(
                isConnect ? Icons.link : Icons.link_off,
                size: 16,
                color: color,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        isConnect
                            ? l10n.historyEventConnect
                            : l10n.historyEventDisconnect,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: color,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        fmt.format(event.serverTimestamp.toLocal()),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$displayLabel · '
                    '${relativeTime(l10n, event.serverTimestamp)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontFamily: monoFamilyFor(isFallback: isFallbackLabel),
                      fontFamilyFallback: monoFallbackFor(
                        isFallback: isFallbackLabel,
                      ),
                    ),
                  ),
                  if (event.rx > 0 || event.tx > 0)
                    Text(
                      l10n.historyBytesPair(
                        formatBytes(event.rx),
                        formatBytes(event.tx),
                      ),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
