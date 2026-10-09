import 'package:fav/core/theme/app_semantic_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

/// Markdown renderer for Help screens. Intercepts three URL schemes:
///
/// - `glossary://<slug>` → calls [onGlossary] with `<slug>`.
/// - `help-error://<code>` → calls [onErrorCode] with `<code>`.
/// - `http(s)://...` → calls [onExternal] with the full [Uri].
///
/// Any handler omitted by the caller silently no-ops on tap.
class HelpMarkdownView extends StatelessWidget {
  /// Creates a [HelpMarkdownView].
  const HelpMarkdownView({
    required this.data,
    this.onGlossary,
    this.onErrorCode,
    this.onExternal,
    super.key,
  });

  /// Markdown source.
  final String data;

  /// Called on `glossary://<slug>` taps.
  final ValueChanged<String>? onGlossary;

  /// Called on `help-error://<code>` taps.
  final ValueChanged<String>? onErrorCode;

  /// Called on `http(s)://...` taps.
  final ValueChanged<Uri>? onExternal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Falls back to the colour scheme when the semantic extension is absent
    // (e.g. a bare-theme widget test); the app always registers it.
    final semantic = theme.extension<AppSemanticColors>();
    final infoSurface =
        semantic?.infoSurface ?? theme.colorScheme.surfaceContainerHighest;
    final info = semantic?.info ?? theme.colorScheme.primary;
    return MarkdownBody(
      data: data,
      selectable: true,
      // The default blockquote styling hardcodes a light-blue background that
      // ignores the theme, leaving light text unreadable on dark mode. Render
      // blockquotes as theme-aware "info" callouts instead.
      styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
        blockquotePadding: const EdgeInsets.all(12),
        blockquoteDecoration: BoxDecoration(
          color: infoSurface,
          borderRadius: BorderRadius.circular(6),
          border: Border(left: BorderSide(color: info, width: 4)),
        ),
      ),
      onTapLink: (text, href, title) {
        if (href == null) return;
        // Use Uri only for scheme detection; extract the authority/path from
        // the raw href to preserve original casing (uri.host is lowercased).
        final uri = Uri.tryParse(href);
        if (uri == null) return;
        switch (uri.scheme) {
          case 'glossary':
            final slug = href.substring('glossary://'.length);
            onGlossary?.call(slug);
          case 'help-error':
            final code = href.substring('help-error://'.length);
            onErrorCode?.call(code);
          case 'http':
          case 'https':
            onExternal?.call(uri);
        }
      },
    );
  }
}
