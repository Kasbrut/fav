import 'package:fav/core/theme/app_dimens.dart';
import 'package:fav/core/widgets/monospace_text.dart';
import 'package:flutter/material.dart';

/// A label/value pair shown on one row, used inside detail cards.
class DetailRow extends StatelessWidget {
  /// Creates a [DetailRow] pairing [label] with [value].
  const DetailRow({
    required this.label,
    required this.value,
    this.monospaceValue = false,
    super.key,
  });

  /// The row caption, shown on the left.
  final String label;

  /// The row value, shown on the right.
  final String value;

  /// Whether the [value] is rendered in the monospace font.
  final bool monospaceValue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: monospaceValue
                ? MonospaceText(value, selectable: false)
                : Text(value, style: theme.textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}
