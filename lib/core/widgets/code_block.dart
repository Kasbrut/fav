import 'package:fav/core/theme/app_dimens.dart';
import 'package:fav/core/theme/app_semantic_colors.dart';
import 'package:fav/core/widgets/monospace_text.dart';
import 'package:flutter/material.dart';

/// A bordered, monospace surface for multi-line code or configuration text.
class CodeBlock extends StatelessWidget {
  /// Creates a [CodeBlock] showing [content].
  const CodeBlock({required this.content, this.selectable = true, super.key});

  /// The code or configuration text to display.
  final String content;

  /// Whether the text can be selected and copied.
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: context.semantic.codeBackground,
        borderRadius: BorderRadius.circular(AppRadii.control),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: MonospaceText(content, selectable: selectable),
    );
  }
}
