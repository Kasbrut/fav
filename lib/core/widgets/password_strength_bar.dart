import 'package:fav/core/theme/app_dimens.dart';
import 'package:fav/core/theme/app_semantic_colors.dart';
import 'package:fav/core/utils/password_strength.dart';
import 'package:fav/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// A coloured bar and label reflecting new-password strength (spec §9.3).
class PasswordStrengthBar extends StatelessWidget {
  /// Creates a [PasswordStrengthBar] for [strength].
  const PasswordStrengthBar({required this.strength, super.key});

  /// The evaluated strength to display.
  final PasswordStrength strength;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final semantic = context.semantic;
    final (value, color, label) = switch (strength) {
      PasswordStrength.weak => (
        0.3,
        theme.colorScheme.error,
        l10n.passwordStrengthWeak,
      ),
      PasswordStrength.fair => (
        0.6,
        semantic.warning,
        l10n.passwordStrengthFair,
      ),
      PasswordStrength.strong => (
        1.0,
        semantic.success,
        l10n.passwordStrengthStrong,
      ),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LinearProgressIndicator(value: value, color: color),
        const SizedBox(height: AppSpacing.xs),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(color: color),
        ),
      ],
    );
  }
}
