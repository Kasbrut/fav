import 'package:fav/core/theme/app_dimens.dart';
import 'package:fav/core/theme/app_semantic_colors.dart';
import 'package:flutter/material.dart';

/// Presentation-level status of an installation step.
///
/// Decoupled from the install feature's domain `StepStatus` so this shared
/// widget does not depend on a feature layer; callers map between the two.
enum InstallStepStatusView {
  /// The step has not started yet.
  pending,

  /// The step is currently running.
  running,

  /// The step finished successfully.
  done,

  /// The step failed.
  error,

  /// The step was skipped.
  skipped,
}

/// A single installation step rendered as a timeline entry: a status
/// indicator linked to its neighbours by a vertical connector, the step
/// name with optional [detail], and an optional [trailing] label.
class InstallStepTile extends StatelessWidget {
  /// Creates an [InstallStepTile].
  const InstallStepTile({
    required this.name,
    required this.status,
    this.detail,
    this.trailing,
    this.position,
    this.isFirst = true,
    this.isLast = true,
    this.semanticLabel,
    super.key,
  });

  /// The human-readable step name.
  final String name;

  /// The current status of the step.
  final InstallStepStatusView status;

  /// Optional supporting detail shown below [name].
  final String? detail;

  /// Optional trailing label, such as the step duration or a running marker.
  final String? trailing;

  /// 1-based step number shown inside the indicator while [status] is pending.
  final int? position;

  /// Whether this is the first tile, hiding the dangling connector above.
  final bool isFirst;

  /// Whether this is the last tile, hiding the dangling connector below.
  final bool isLast;

  /// Screen-reader label announcing the step name and its status as one
  /// phrase. When provided, the visual subtree (icon-only status indicator,
  /// name, detail, trailing) is collapsed into this single announcement so the
  /// step's state is perceivable without sight; the icon alone conveys nothing.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final lineColor = scheme.outlineVariant;
    final tile = IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 28,
            child: Column(
              children: [
                Expanded(
                  child: Container(width: 2, color: isFirst ? null : lineColor),
                ),
                _StepIndicator(status: status, position: position),
                Expanded(
                  child: Container(width: 2, color: isLast ? null : lineColor),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(
                top: AppSpacing.xs,
                bottom: AppSpacing.lg,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: theme.textTheme.bodyLarge),
                  if (detail != null) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      detail!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (trailing != null)
            Padding(
              padding: const EdgeInsets.only(
                left: AppSpacing.sm,
                top: AppSpacing.xs,
              ),
              child: Text(
                trailing!,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: status == InstallStepStatusView.running
                      ? scheme.primary
                      : scheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
    if (semanticLabel == null) {
      return tile;
    }
    return Semantics(
      container: true,
      label: semanticLabel,
      child: ExcludeSemantics(child: tile),
    );
  }
}

/// The 22 px status indicator at the start of an [InstallStepTile] row.
class _StepIndicator extends StatelessWidget {
  const _StepIndicator({required this.status, this.position});

  final InstallStepStatusView status;
  final int? position;

  static const double _size = 22;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    switch (status) {
      case InstallStepStatusView.running:
        return const SizedBox(
          width: _size,
          height: _size,
          child: Padding(
            padding: EdgeInsets.all(2),
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      case InstallStepStatusView.done:
        return Icon(
          Icons.check_circle,
          size: _size,
          color: context.semantic.success,
        );
      case InstallStepStatusView.error:
        return Icon(Icons.error, size: _size, color: scheme.error);
      case InstallStepStatusView.skipped:
        return Icon(
          Icons.remove_circle,
          size: _size,
          color: scheme.onSurfaceVariant,
        );
      case InstallStepStatusView.pending:
        return Container(
          width: _size,
          height: _size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: scheme.surface,
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Text(
            position?.toString() ?? '',
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        );
    }
  }
}
