import 'package:fav/core/theme/app_text_theme.dart';
import 'package:flutter/material.dart';

/// Text rendered in the platform monospace font.
///
/// Used for code, configuration, SHA-256 hashes and host-key fingerprints —
/// the single place that applies the monospace font family.
class MonospaceText extends StatelessWidget {
  /// Creates a [MonospaceText] showing [data].
  const MonospaceText(
    this.data, {
    this.selectable = true,
    this.style,
    super.key,
  });

  /// The monospace text to display.
  final String data;

  /// Whether the text can be selected and copied.
  final bool selectable;

  /// Optional style merged on top of the monospace defaults.
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final base = (Theme.of(context).textTheme.bodySmall ?? const TextStyle())
        .copyWith(
          fontFamily: kMonospacePrimaryFont,
          fontFamilyFallback: kMonospaceFontFallback,
        )
        .merge(style);
    return selectable
        ? SelectableText(data, style: base)
        : Text(data, style: base);
  }
}
