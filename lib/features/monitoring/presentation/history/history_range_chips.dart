import 'package:fav/core/theme/app_dimens.dart';
import 'package:fav/features/monitoring/application/history_provider.dart';
import 'package:fav/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Two `ChoiceChip`s that pick the visible time window for the history.
class HistoryRangeChips extends ConsumerWidget {
  /// Creates a [HistoryRangeChips] bound to [serverId]'s filter state.
  const HistoryRangeChips({required this.serverId, super.key});

  /// Server whose filter state these chips control.
  final String serverId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final filter = ref.watch(historyFilterProvider(serverId));
    final controller = ref.read(historyFilterProvider(serverId).notifier);
    return Wrap(
      spacing: AppSpacing.sm,
      children: [
        ChoiceChip(
          label: Text(l10n.historyRange24h),
          selected: filter.range == HistoryRange.last24h,
          onSelected: (_) => controller.setRange(HistoryRange.last24h),
        ),
        ChoiceChip(
          label: Text(l10n.historyRange7d),
          selected: filter.range == HistoryRange.last7d,
          onSelected: (_) => controller.setRange(HistoryRange.last7d),
        ),
      ],
    );
  }
}
