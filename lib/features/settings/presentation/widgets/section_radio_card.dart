import 'package:fav/core/theme/app_dimens.dart';
import 'package:fav/core/widgets/app_card.dart';
import 'package:flutter/material.dart';

/// One option in a [SectionRadioCard].
class SectionRadioOption<T> {
  /// Creates an option.
  const SectionRadioOption({required this.value, required this.label});

  /// Value emitted when the user selects this option.
  final T value;

  /// Localized label shown next to the radio.
  final String label;
}

/// A typed radio-group inside an [AppCard]. Used for Settings sections
/// like Appearance and Language.
class SectionRadioCard<T> extends StatelessWidget {
  /// Creates the card.
  const SectionRadioCard({
    required this.options,
    required this.value,
    required this.onChanged,
    super.key,
  });

  /// Available options in display order.
  final List<SectionRadioOption<T>> options;

  /// Currently selected value.
  final T value;

  /// Called when the user picks a new option.
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: RadioGroup<T>(
        groupValue: value,
        onChanged: (next) {
          if (next != null && next != value) onChanged(next);
        },
        child: Column(
          children: [
            for (final option in options)
              RadioListTile<T>(
                title: Text(option.label),
                value: option.value,
              ),
          ],
        ),
      ),
    );
  }
}
