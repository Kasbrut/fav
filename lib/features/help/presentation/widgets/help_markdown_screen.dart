import 'package:fav/core/theme/app_dimens.dart';
import 'package:fav/core/widgets/empty_state.dart';
import 'package:fav/core/widgets/responsive_app_bar.dart';
import 'package:fav/core/widgets/responsive_content.dart';
import 'package:fav/features/help/presentation/external_link.dart';
import 'package:fav/features/help/presentation/widgets/help_markdown_view.dart';
import 'package:fav/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:go_router/go_router.dart';

/// Scaffold shared by the static Help pages (FAQ, getting started,
/// firewall guide, resources, donate): renders
/// `lib/assets/help/<assetStem>.<locale>.md` with a fallback to the English
/// file, caches the load per locale — the old per-screen FutureBuilders
/// re-read the asset on every rebuild — and shows a retryable error view
/// instead of an endless spinner when both loads fail (deep-audit low nit).
class HelpMarkdownScreen extends StatefulWidget {
  /// Creates the screen.
  const HelpMarkdownScreen({
    required this.title,
    required this.assetStem,
    super.key,
    this.loadAsset,
  });

  /// AppBar title.
  final String title;

  /// Directory + basename under `lib/assets/help/`, e.g. `faq/faq` →
  /// `lib/assets/help/faq/faq.<locale>.md`.
  final String assetStem;

  /// Asset loader, injectable for tests; defaults to [rootBundle].
  final Future<String> Function(String path)? loadAsset;

  @override
  State<HelpMarkdownScreen> createState() => _HelpMarkdownScreenState();
}

class _HelpMarkdownScreenState extends State<HelpMarkdownScreen> {
  Future<String>? _markdown;
  String? _locale;

  Future<String> Function(String path) get _load =>
      widget.loadAsset ?? rootBundle.loadString;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // One load per locale: re-resolve only when the app language changes.
    final locale = Localizations.localeOf(context).languageCode;
    if (locale != _locale) {
      _locale = locale;
      _markdown = _loadFor(locale);
    }
  }

  Future<String> _loadFor(String locale) async {
    final base = 'lib/assets/help/${widget.assetStem}';
    try {
      return await _load('$base.$locale.md');
    } on Object catch (_) {
      // Fallback to EN if the localized file is missing.
      return _load('$base.en.md');
    }
  }

  void _retry() {
    // Block body on purpose: an arrow closure would RETURN the assigned
    // Future and trip setState's returned-a-Future assert.
    setState(() {
      _markdown = _loadFor(_locale!);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: ResponsiveAppBar(
        title: widget.title,
        maxContentWidth: AppSizes.contentMaxWidth,
      ),
      body: ResponsiveContent(
        child: FutureBuilder<String>(
          future: _markdown,
          builder: (context, snap) {
            if (snap.hasError) {
              return EmptyState(
                icon: Icons.menu_book_outlined,
                title: l10n.helpContentLoadError,
                action: TextButton(
                  onPressed: _retry,
                  child: Text(l10n.actionRetry),
                ),
              );
            }
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            return Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.xxl,
              ),
              child: SingleChildScrollView(
                child: HelpMarkdownView(
                  data: snap.data!,
                  onGlossary: (slug) => context.push('/help/glossary/$slug'),
                  onErrorCode: (code) => context.push('/help/errors/$code'),
                  onExternal: (uri) => confirmAndLaunchExternal(context, uri),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
