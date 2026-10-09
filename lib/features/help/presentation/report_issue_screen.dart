import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:fav/core/errors/app_exception.dart';
import 'package:fav/core/theme/app_dimens.dart';
import 'package:fav/core/theme/app_text_theme.dart';
import 'package:fav/core/utils/app_logger.dart';
import 'package:fav/core/utils/log_scrubber.dart';
import 'package:fav/core/widgets/responsive_app_bar.dart';
import 'package:fav/features/help/application/recent_errors_provider.dart';
import 'package:fav/features/help/data/issue_url_builder.dart';
import 'package:fav/features/settings/application/extended_diagnostic_provider.dart';
import 'package:fav/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// In-app form that composes a prefilled GitHub issue URL via
/// [IssueUrlBuilder]. The diagnostic payload is loaded asynchronously after
/// first frame and is fully sanitized — no secrets, no server identifiers.
class ReportIssueScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const ReportIssueScreen({super.key, this.urlLauncher});

  /// Test seam for opening the issue URL; production uses `url_launcher`.
  final Future<bool> Function(Uri url)? urlLauncher;

  @override
  ConsumerState<ReportIssueScreen> createState() => _ReportIssueScreenState();
}

class _ReportIssueScreenState extends ConsumerState<ReportIssueScreen> {
  final _formKey = GlobalKey<FormState>();
  final _doing = TextEditingController();
  final _expected = TextEditingController();
  final _happened = TextEditingController();
  ErrorCode? _code;
  IssueDiagnostic? _diagnostic;
  bool _submitting = false;
  bool _includeExtendedDiag = false;
  bool _attachLogs = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadDiagnostic());
  }

  Future<void> _loadDiagnostic() async {
    // Build a defensive snapshot — every plugin call wrapped, every failure
    // degraded to 'unknown' so the form is always submittable.
    var appVersion = 'unknown';
    var osVersion = 'unknown';
    try {
      final pkg = await PackageInfo.fromPlatform();
      appVersion = '${pkg.version}+${pkg.buildNumber}';
    } on Object {
      // Plugin channel unavailable (tests, some build configs) — keep
      // the placeholder.
    }
    try {
      final info = DeviceInfoPlugin();
      if (Platform.isIOS) {
        final ios = await info.iosInfo;
        osVersion = ios.systemVersion;
      } else if (Platform.isAndroid) {
        final a = await info.androidInfo;
        osVersion = a.version.release;
      }
    } on Object {
      // Keep the placeholder.
    }
    if (!mounted) return;
    final locale = Localizations.localeOf(context);
    setState(() {
      _diagnostic = IssueDiagnostic(
        appVersion: appVersion,
        platform: Platform.operatingSystem,
        osVersion: osVersion,
        locale: _formatLocale(locale),
        recentErrorCodes: ref.read(recentErrorsProvider),
      );
    });
  }

  IssueDiagnostic _safeDiagnostic() {
    if (_diagnostic != null) return _diagnostic!;
    // Submit-time fallback in case the load hasn't completed yet.
    final locale = Localizations.localeOf(context);
    return IssueDiagnostic(
      appVersion: 'unknown',
      platform: Platform.operatingSystem,
      osVersion: 'unknown',
      locale: _formatLocale(locale),
      recentErrorCodes: ref.read(recentErrorsProvider),
    );
  }

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    // Capture the locale before the await; the extended diagnostic call is slow
    // (PackageInfo + DeviceInfo + box scans), so guard context/ref use after it
    // in case the user navigated away mid-submit (audit M12).
    final uiLocale = Localizations.localeOf(context);
    final extended = _includeExtendedDiag
        ? await ref.read(extendedDiagnosticProvider)(uiLocale: uiLocale)
        : null;
    if (!mounted) return;
    final issue = IssueUrlBuilder.build(
      fields: ReportIssueFields(
        whatYouWereDoing: _doing.text,
        whatYouExpected: _expected.text,
        whatHappened: _happened.text,
        errorCode: _code?.id,
      ),
      diagnostic: _safeDiagnostic(),
      extendedDiagnostic: extended,
    );
    _copiedLogs = null;
    if (_attachLogs) {
      // Opt-in log attachment (spec §10-adjacent): the scrubbed lines are
      // shown in an editable preview and travel via the clipboard, never
      // the URL (its ~8 KB cap) — the user pastes them into the issue.
      // null = dismissed (abort); false = continue without logs (audit L3).
      final choice = await _showLogsPreview();
      if (choice == null) {
        if (mounted) setState(() => _submitting = false);
        return;
      }
      if (!mounted) return;
    }
    var launched = false;
    try {
      launched = await _launch(issue.url);
    } on Object {
      launched = false;
    }
    if (!launched && mounted) {
      await _showFallback(issue);
    }
    if (mounted) setState(() => _submitting = false);
  }

  Future<bool> _launch(Uri url) {
    final override = widget.urlLauncher;
    if (override != null) {
      return override(url);
    }
    return launchUrl(url, mode: LaunchMode.externalApplication);
  }

  static String _formatLocale(Locale locale) {
    final country = locale.countryCode;
    return (country == null || country.isEmpty)
        ? locale.languageCode
        : '${locale.languageCode}_$country';
  }

  /// The scrubbed (possibly edited) log text copied during this submission;
  /// appended to the fallback dialog's copy so it cannot be clobbered
  /// (audit L2). Null when no logs were attached.
  String? _copiedLogs;

  /// Shows the editable, pre-scrubbed log preview. Returns true when the
  /// user copied the (possibly edited) text, false to continue without
  /// logs, null when dismissed (aborts the submission).
  Future<bool?> _showLogsPreview() async {
    final l10n = AppLocalizations.of(context)!;
    final scrubbed = scrubLog(ref.read(appLogBufferProvider).lines);
    final controller = TextEditingController(text: scrubbed);
    try {
      return await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l10n.helpReportLogsPreviewTitle),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.helpReportLogsPreviewBody,
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
                const SizedBox(height: AppSpacing.md),
                Flexible(
                  child: TextField(
                    controller: controller,
                    maxLines: 12,
                    minLines: 6,
                    style: const TextStyle(
                      fontFamily: kMonospacePrimaryFont,
                      fontFamilyFallback: kMonospaceFontFallback,
                      fontSize: 12,
                    ),
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(l10n.actionCancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l10n.helpReportLogsContinueWithout),
            ),
            FilledButton(
              onPressed: () async {
                _copiedLogs = controller.text;
                await Clipboard.setData(
                  ClipboardData(text: controller.text),
                );
                if (ctx.mounted) Navigator.of(ctx).pop(true);
              },
              child: Text(l10n.helpReportLogsCopyContinue),
            ),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  Future<void> _showFallback(IssueUrl issue) async {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        var openFailed = false;
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return _FallbackDialog(
              l10n: l10n,
              theme: theme,
              issue: issue,
              openFailed: openFailed,
              onOpenLink: () async {
                try {
                  final ok = await _launch(issue.url);
                  if (!ok) setLocal(() => openFailed = true);
                } on Object {
                  setLocal(() => openFailed = true);
                }
              },
              onCopy: () async {
                // Keep the previously copied logs: overwriting the clipboard
                // with just the body would lose what the user was told to
                // paste (audit L2).
                final logs = _copiedLogs;
                await Clipboard.setData(
                  ClipboardData(
                    text: logs == null
                        ? issue.plaintextBody
                        : '${issue.plaintextBody}\n\n--- logs ---\n$logs',
                  ),
                );
                if (ctx.mounted) Navigator.of(ctx).pop();
              },
              onClose: () => Navigator.of(ctx).pop(),
            );
          },
        );
      },
    );
  }

  @override
  void dispose() {
    _doing.dispose();
    _expected.dispose();
    _happened.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: ResponsiveAppBar(
        title: l10n.helpReportTitle,
        maxContentWidth: AppSizes.contentMaxWidth,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.xxl,
          ),
          children: [
            Text(l10n.helpReportIntro),
            const SizedBox(height: AppSpacing.lg),
            _BoundedField(
              controller: _doing,
              label: l10n.helpReportWhatDoing,
              hint: l10n.helpReportWhatDoingHint,
            ),
            const SizedBox(height: AppSpacing.md),
            _BoundedField(
              controller: _expected,
              label: l10n.helpReportWhatExpected,
              hint: l10n.helpReportWhatExpectedHint,
            ),
            const SizedBox(height: AppSpacing.md),
            _BoundedField(
              controller: _happened,
              label: l10n.helpReportWhatHappened,
              hint: l10n.helpReportWhatHappenedHint,
            ),
            const SizedBox(height: AppSpacing.md),
            DropdownButtonFormField<ErrorCode?>(
              initialValue: _code,
              decoration: InputDecoration(
                labelText: l10n.helpReportErrorCode,
              ),
              items: [
                DropdownMenuItem<ErrorCode?>(
                  child: Text(l10n.helpReportErrorCodeNone),
                ),
                for (final c in ErrorCode.values)
                  DropdownMenuItem<ErrorCode?>(
                    value: c,
                    child: Text(c.id),
                  ),
              ],
              onChanged: (v) => setState(() => _code = v),
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.warning_amber, color: theme.colorScheme.tertiary),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: Text(l10n.helpReportSecurityWarning)),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _includeExtendedDiag,
              onChanged: (v) =>
                  setState(() => _includeExtendedDiag = v ?? false),
              title: Text(l10n.helpReportExtendedDiagCheckbox),
              subtitle: Text(l10n.helpReportExtendedDiagSubtitle),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _attachLogs,
              onChanged: (v) => setState(() => _attachLogs = v ?? false),
              title: Text(l10n.helpReportAttachLogs),
              subtitle: Text(l10n.helpReportLogsPreviewBody),
            ),
            const SizedBox(height: AppSpacing.md),
            if (_diagnostic != null)
              ExpansionTile(
                title: Text(l10n.helpReportTechnicalDataHeader),
                children: [
                  ListTile(
                    title: Text(
                      l10n.helpReportDiagAppLine(_diagnostic!.appVersion),
                    ),
                  ),
                  ListTile(
                    title: Text(
                      l10n.helpReportDiagPlatformLine(
                        _diagnostic!.platform,
                        _diagnostic!.osVersion,
                      ),
                    ),
                  ),
                  ListTile(
                    title: Text(
                      l10n.helpReportDiagLocaleLine(_diagnostic!.locale),
                    ),
                  ),
                  ListTile(
                    title: Text(
                      l10n.helpReportDiagRecentLine(
                        _diagnostic!.recentErrorCodes.join(', '),
                      ),
                    ),
                  ),
                ],
              ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton.icon(
              onPressed: _submitting ? null : _submit,
              icon: const Icon(Icons.bug_report),
              label: Text(l10n.helpReportOpenGithub),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextButton(
              onPressed: _submitting ? null : () => Navigator.of(context).pop(),
              child: Text(l10n.helpReportCancel),
            ),
          ],
        ),
      ),
    );
  }
}

class _BoundedField extends StatelessWidget {
  const _BoundedField({
    required this.controller,
    required this.label,
    required this.hint,
  });

  final TextEditingController controller;
  final String label;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      maxLength: IssueUrlBuilder.maxFieldLength,
      maxLines: 4,
      minLines: 2,
      decoration: InputDecoration(labelText: label, hintText: hint),
    );
  }
}

class _FallbackDialog extends StatelessWidget {
  const _FallbackDialog({
    required this.l10n,
    required this.theme,
    required this.issue,
    required this.openFailed,
    required this.onOpenLink,
    required this.onCopy,
    required this.onClose,
  });

  final AppLocalizations l10n;
  final ThemeData theme;
  final IssueUrl issue;
  final bool openFailed;
  final Future<void> Function() onOpenLink;
  final Future<void> Function() onCopy;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(l10n.helpReportFallbackTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.helpReportFallbackInstructions),
            const SizedBox(height: AppSpacing.md),
            Text(
              l10n.helpReportFallbackBodyLabel,
              style: theme.textTheme.labelSmall,
            ),
            const SizedBox(height: AppSpacing.xs),
            SelectableText(issue.plaintextBody),
            if (openFailed) ...[
              const SizedBox(height: AppSpacing.md),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 18,
                    color: theme.colorScheme.error,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      l10n.helpReportFallbackOpenFailed,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: onClose,
          child: Text(l10n.helpReportFallbackClose),
        ),
        TextButton(
          onPressed: onCopy,
          child: Text(l10n.helpReportFallbackCopy),
        ),
        FilledButton(
          onPressed: onOpenLink,
          child: Text(l10n.helpReportFallbackOpenLink),
        ),
      ],
    );
  }
}
