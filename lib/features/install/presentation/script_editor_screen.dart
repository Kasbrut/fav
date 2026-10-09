import 'dart:async';
import 'dart:convert';

import 'package:fav/core/crypto/sha256_hasher.dart';
import 'package:fav/core/theme/app_dimens.dart';
import 'package:fav/core/theme/app_semantic_colors.dart';
import 'package:fav/core/theme/app_text_theme.dart';
import 'package:fav/core/utils/line_diff.dart';
import 'package:fav/core/utils/suspicious_script_patterns.dart';
import 'package:fav/core/widgets/monospace_text.dart';
import 'package:fav/core/widgets/primary_button.dart';
import 'package:fav/core/widgets/responsive_app_bar.dart';
import 'package:fav/core/widgets/responsive_content.dart';
import 'package:fav/core/widgets/secondary_button.dart';
import 'package:fav/core/widgets/status_badge.dart';
import 'package:fav/features/install/data/scripts/asset_script_repository.dart';
import 'package:fav/features/install/data/scripts/editable_script_catalog.dart';
import 'package:fav/features/install/data/scripts/effective_script_resolver.dart';
import 'package:fav/features/install/data/scripts/hive_user_script_repository.dart';
import 'package:fav/features/install/domain/user_script.dart';
import 'package:fav/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:highlight/languages/bash.dart' show bash;

/// Viewer + editor for every bundled script (RF-09, RF-10, spec §6.3, §8).
///
/// Each file has two versions: the immutable bundled original and an editable
/// override stored in the encrypted `scripts` box keyed by relative path. The
/// override is always the version uploaded/run; the original is the backup the
/// "Restore" actions return to. Lives in Settings → Danger Zone (the scripts
/// run as root, so editing them is a destructive-class operation).
class ScriptEditorScreen extends ConsumerStatefulWidget {
  /// Creates the script editor screen.
  const ScriptEditorScreen({super.key});

  @override
  ConsumerState<ScriptEditorScreen> createState() => _ScriptEditorScreenState();
}

class _ScriptEditorScreenState extends ConsumerState<ScriptEditorScreen> {
  final CodeController _code = CodeController(language: bash);

  bool _loading = true;
  Object? _loadError;

  /// Paths shown in the picker, in catalog order (only those that loaded).
  List<String> _paths = const [];

  /// Immutable bundled original content, per path.
  final Map<String, String> _defaults = {};

  /// Active override content, per path (absent ⇒ no override / uses original).
  final Map<String, String> _overrides = {};

  String _selectedPath = kOrchestratorScript;

  /// Baseline content of the selected file: what "unchanged" means right now.
  String _loadedContent = '';

  bool _editing = false;
  bool _showDiff = false;
  bool _showHash = false;

  bool get _isCustomized => _overrides.containsKey(_selectedPath);

  String get _selectedDefault => _defaults[_selectedPath] ?? '';

  /// The content to treat as the selected file's baseline.
  String _baselineFor(String path) => _overrides[path] ?? _defaults[path] ?? '';

  String get _currentHash => sha256Hex(utf8.encode(_code.text));

  bool get _dirty => _editing && _code.text != _loadedContent;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _code
      ..removeListener(_onCodeChanged)
      ..dispose();
    super.dispose();
  }

  /// Loads every editable script's original + override.
  Future<void> _load() async {
    try {
      final resolver = await ref.read(effectiveScriptResolverProvider.future);
      final repo = ref.read(userScriptRepositoryProvider);
      final defaults = <String, String>{};
      final overrides = <String, String>{};
      final paths = <String>[];
      for (final path in kEditableScriptPaths) {
        final original = await resolver.originalBytesFor(path);
        defaults[path] = utf8.decode(original);
        paths.add(path);
        final override = await repo.getById(path);
        if (override != null) {
          overrides[path] = override.content;
        }
      }
      if (!mounted) {
        return;
      }
      _paths = paths;
      _defaults
        ..clear()
        ..addAll(defaults);
      _overrides
        ..clear()
        ..addAll(overrides);
      _selectedPath = kOrchestratorScript;
      _loadedContent = _baselineFor(_selectedPath);
      // fullText, not .text — see _setCode.
      _code.fullText = _loadedContent;
      _code.addListener(_onCodeChanged);
      setState(() => _loading = false);
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _loadError = error;
          _loading = false;
        });
      }
    }
  }

  void _onCodeChanged() => setState(() {});

  /// Sets the editor text programmatically without firing [_onCodeChanged].
  ///
  /// Must go through [CodeController.fullText]: a plain `.text =` is treated
  /// by the controller as an *edit* of the current document and mangles a
  /// full-document swap (the newly selected file rendered as the tail of the
  /// previous one, cut mid-line — live editor corruption, 2026-08-19).
  void _setCode(String text) {
    _code
      ..removeListener(_onCodeChanged)
      ..fullText = text
      ..addListener(_onCodeChanged);
  }

  void _selectFile(String path) {
    final baseline = _baselineFor(path);
    _setCode(baseline);
    setState(() {
      _selectedPath = path;
      _loadedContent = baseline;
      _editing = false;
      _showDiff = false;
      _showHash = false;
    });
  }

  void _customize() => setState(() => _editing = true);

  void _discardEditing() {
    _setCode(_loadedContent);
    setState(() => _editing = false);
  }

  Future<void> _restoreDefault() async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await _confirm(
      title: l10n.scriptEditorRestoreConfirmTitle,
      body: l10n.scriptEditorRestoreConfirmBody,
      action: l10n.scriptEditorRestore,
    );
    if (confirmed != true) {
      return;
    }
    await ref.read(userScriptRepositoryProvider).delete(_selectedPath);
    _overrides.remove(_selectedPath);
    _setCode(_selectedDefault);
    setState(() {
      _loadedContent = _selectedDefault;
      _editing = false;
      _showDiff = false;
    });
  }

  /// Deletes every override in one go, restoring all originals. Leaves the
  /// rest of the local data (servers, peers, preferences) untouched.
  Future<void> _restoreAll() async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await _confirm(
      title: l10n.scriptEditorRestoreAllConfirmTitle,
      body: l10n.scriptEditorRestoreAllConfirmBody,
      action: l10n.scriptEditorRestoreAll,
    );
    if (confirmed != true) {
      return;
    }
    final repo = ref.read(userScriptRepositoryProvider);
    for (final path in _overrides.keys.toList()) {
      await repo.delete(path);
    }
    _overrides.clear();
    _setCode(_selectedDefault);
    setState(() {
      _loadedContent = _selectedDefault;
      _editing = false;
      _showDiff = false;
    });
    if (mounted) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.scriptEditorRestoreAllDone)),
      );
    }
  }

  Future<bool?> _confirm({
    required String title,
    required String body,
    required String action,
  }) {
    final l10n = AppLocalizations.of(context)!;
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.actionCancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(action),
          ),
        ],
      ),
    );
  }

  Future<void> _copyHash() async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: _currentHash));
    if (!mounted) {
      return;
    }
    messenger.showSnackBar(SnackBar(content: Text(l10n.scriptHashCopied)));
  }

  Future<void> _openPicker() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => _ScriptPickerSheet(
        paths: _paths,
        overridden: _overrides.keys.toSet(),
        selected: _selectedPath,
      ),
    );
    if (selected != null && selected != _selectedPath) {
      _selectFile(selected);
    }
  }

  Future<bool?> _confirmSuspicious(List<SuspiciousPattern> patterns) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    // Cap the listing so a pathological file does not blow up the dialog.
    final shown = patterns.take(8).toList();
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.scriptImportSuspiciousTitle),
        content: ConstrainedBox(
          // Cap the width on tablets but let it shrink on narrow phones.
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.scriptImportSuspiciousBody),
              const SizedBox(height: AppSpacing.md),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final p in shown) ...[
                        Text(
                          l10n.scriptImportLine(p.line),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        MonospaceText(p.text),
                        const SizedBox(height: AppSpacing.xs),
                      ],
                      if (patterns.length > shown.length)
                        Text(
                          '+${patterns.length - shown.length}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.actionCancel),
          ),
          // Affirmative action follows the app convention (filled), but in the
          // error colour because importing unverified code is the risky path.
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.error,
              foregroundColor: theme.colorScheme.onError,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.actionImportAnyway),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: ResponsiveAppBar(
        title: l10n.scriptEditorTitle,
        maxContentWidth: AppSizes.contentMaxWidth,
        actions: [
          // The only overflow action is "Restore all originals"; show the menu
          // only when there is at least one override to restore.
          if (!_loading && _loadError == null && _overrides.isNotEmpty)
            _buildOverflow(l10n),
        ],
      ),
      body: ResponsiveContent(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _loadError != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: Text('$_loadError', textAlign: TextAlign.center),
                ),
              )
            : _buildBody(context, l10n),
      ),
    );
  }

  Widget _buildOverflow(AppLocalizations l10n) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert),
      onSelected: (value) {
        if (value == 'restore_all') {
          unawaited(_restoreAll());
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'restore_all',
          child: Text(l10n.scriptEditorRestoreAll),
        ),
      ],
    );
  }

  Widget _buildBody(BuildContext context, AppLocalizations l10n) {
    final theme = Theme.of(context);
    final lineCount = _code.text.split('\n').length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.sm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _FileSelector(
                path: _selectedPath,
                enabled: _paths.length > 1 && !_editing,
                onTap: _openPicker,
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  _statusBadge(l10n),
                  if (_editing) ...[
                    const SizedBox(width: AppSpacing.sm),
                    StatusBadge(
                      label: l10n.scriptEditorEditingBadge,
                      variant: StatusBadgeVariant.info,
                      icon: Icons.edit_outlined,
                    ),
                  ],
                  const Spacer(),
                  Text(
                    l10n.scriptEditorMeta(lineCount),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Expanded(
          child: _showDiff
              ? _DiffView(original: _selectedDefault, modified: _code.text)
              : _buildCodeField(theme),
        ),
        _buildFooter(context, l10n),
      ],
    );
  }

  Widget _statusBadge(AppLocalizations l10n) {
    return _isCustomized
        ? StatusBadge(
            label: l10n.scriptEditorModifiedBadge,
            variant: StatusBadgeVariant.warning,
          )
        : StatusBadge(label: l10n.scriptEditorDefault);
  }

  // Shared monospace metrics so the gutter lines up with the code.
  static const double _codeFontSize = 13;
  static const double _codeLineHeight = 1.4;

  Widget _buildCodeField(ThemeData theme) {
    final scheme = theme.colorScheme;
    const codeStyle = TextStyle(
      fontFamily: kMonospacePrimaryFont,
      fontFamilyFallback: kMonospaceFontFallback,
      fontSize: _codeFontSize,
      height: _codeLineHeight,
    );
    // flutter_code_editor draws the line-number gutter itself, sharing the
    // code field's line metrics (the gutter font is taken from the widget
    // style), so the numbers always line up. We only theme it, and tighten
    // its width to the actual digit count (the 80px default wastes a lot of
    // space to the left of the numbers on a narrow phone).
    //
    // The visible number column = GutterStyle.width minus everything the
    // gutter reserves out of it: the hidden error + folding columns (16px
    // each, see gutter.dart) and its own right margin. So the width we pass
    // must be: measured number width + slack + 32 + margin.
    const hiddenColumnsOverhead = 32.0;
    const gutterMargin = AppSpacing.xs;
    // Measure the widest line number exactly (font-independent) instead of
    // estimating per-digit, so the numbers never wrap.
    final maxLabel = _code.text.split('\n').length.toString();
    final painter = TextPainter(
      text: TextSpan(text: maxLabel, style: codeStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    final gutterWidth =
        hiddenColumnsOverhead + gutterMargin + painter.width + AppSpacing.md;
    painter.dispose();
    return CodeTheme(
      data: CodeThemeData(styles: _highlightStyles(theme)),
      child: CodeField(
        controller: _code,
        readOnly: !_editing,
        expands: true,
        background: scheme.surfaceContainerHighest,
        textStyle: codeStyle,
        gutterStyle: GutterStyle(
          showErrors: false,
          showFoldingHandles: false,
          width: gutterWidth,
          margin: gutterMargin,
          background: scheme.surfaceContainerHigh,
          textStyle: codeStyle.copyWith(color: scheme.onSurfaceVariant),
        ),
      ),
    );
  }

  Widget _buildFooter(BuildContext context, AppLocalizations l10n) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            AppSpacing.md,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildVerify(theme, l10n),
              const SizedBox(height: AppSpacing.sm),
              ..._buildActions(l10n),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVerify(ThemeData theme, AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _showHash = !_showHash),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Row(
              children: [
                Icon(
                  _showHash ? Icons.expand_less : Icons.expand_more,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  l10n.scriptEditorVerify,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_showHash) ...[
          const SizedBox(height: AppSpacing.xs),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: MonospaceText(_currentHash)),
              IconButton(
                tooltip: l10n.actionCopy,
                icon: const Icon(Icons.copy_outlined, size: 18),
                onPressed: _copyHash,
              ),
            ],
          ),
        ],
      ],
    );
  }

  List<Widget> _buildActions(AppLocalizations l10n) {
    if (_showDiff) {
      return [
        SecondaryButton(
          label: l10n.scriptEditorHideChanges,
          icon: Icons.code,
          onPressed: () => setState(() => _showDiff = false),
        ),
      ];
    }
    if (_editing) {
      return [
        PrimaryButton(
          label: l10n.actionSave,
          onPressed: _dirty ? () => unawaited(_save()) : null,
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: SecondaryButton(
                label: l10n.scriptEditorDiscard,
                onPressed: _discardEditing,
              ),
            ),
            if (_isCustomized) ...[
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: SecondaryButton(
                  label: l10n.scriptEditorRestore,
                  onPressed: () => unawaited(_restoreDefault()),
                ),
              ),
            ],
          ],
        ),
      ];
    }
    return [
      SecondaryButton(
        label: l10n.actionCustomize,
        icon: Icons.edit_outlined,
        onPressed: _customize,
      ),
      if (_isCustomized) ...[
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: SecondaryButton(
                label: l10n.scriptEditorViewChanges,
                icon: Icons.difference_outlined,
                onPressed: () => setState(() => _showDiff = true),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: SecondaryButton(
                label: l10n.scriptEditorRestore,
                icon: Icons.restore,
                onPressed: () => unawaited(_restoreDefault()),
              ),
            ),
          ],
        ),
      ],
    ];
  }

  Future<void> _save() async {
    final content = _code.text;
    final repo = ref.read(userScriptRepositoryProvider);
    if (content == _selectedDefault) {
      // Content identical to the original is not a customization.
      await repo.delete(_selectedPath);
      _overrides.remove(_selectedPath);
    } else {
      // The override will be uploaded and run as root: warn on common
      // remote-exec patterns before persisting it (spec §8.6), the same gate
      // applied to imports.
      final suspicious = detectSuspiciousScriptPatterns(content);
      if (suspicious.isNotEmpty) {
        final proceed = await _confirmSuspicious(suspicious);
        if (proceed != true || !mounted) {
          return;
        }
      }
      await repo.save(
        UserScript.fromContent(
          id: _selectedPath,
          content: content,
          createdAt: DateTime.now(),
        ),
      );
      _overrides[_selectedPath] = content;
    }
    if (!mounted) {
      return;
    }
    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _loadedContent = content;
      _editing = false;
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l10n.scriptEditorSaved)));
  }

  /// Syntax-highlight colours for bash, derived from the app theme so the
  /// editor adapts to light and dark mode.
  Map<String, TextStyle> _highlightStyles(ThemeData theme) {
    final scheme = theme.colorScheme;
    final semantic = theme.extension<AppSemanticColors>();
    final muted = TextStyle(color: scheme.onSurfaceVariant);
    return {
      'root': TextStyle(color: scheme.onSurface),
      'comment': muted.copyWith(fontStyle: FontStyle.italic),
      'meta': muted,
      'keyword': TextStyle(color: scheme.primary),
      'built_in': TextStyle(color: scheme.primary),
      'literal': TextStyle(color: scheme.primary),
      'string': TextStyle(color: semantic?.success ?? scheme.tertiary),
      'variable': TextStyle(color: scheme.tertiary),
      'number': TextStyle(color: scheme.tertiary),
      'title': TextStyle(color: scheme.onSurface),
    };
  }
}

/// The tappable row that shows the current script path and opens the picker.
class _FileSelector extends StatelessWidget {
  const _FileSelector({
    required this.path,
    required this.enabled,
    required this.onTap,
  });

  final String path;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(AppRadii.control),
      child: Container(
        constraints: const BoxConstraints(minHeight: AppSizes.minTouchTarget),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(AppRadii.control),
          border: Border.all(color: theme.colorScheme.outline),
        ),
        child: Row(
          children: [
            Icon(
              Icons.description_outlined,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                path,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: kMonospacePrimaryFont,
                  fontFamilyFallback: kMonospaceFontFallback,
                  fontSize: 13,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
            if (enabled)
              Icon(
                Icons.unfold_more,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet listing every editable script, grouped, for selection.
class _ScriptPickerSheet extends StatelessWidget {
  const _ScriptPickerSheet({
    required this.paths,
    required this.overridden,
    required this.selected,
  });

  final List<String> paths;
  final Set<String> overridden;
  final String selected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    const order = [
      ScriptGroup.installer,
      ScriptGroup.hardening,
      ScriptGroup.monitoring,
      ScriptGroup.peers,
    ];
    final labels = {
      ScriptGroup.installer: l10n.scriptGroupInstaller,
      ScriptGroup.hardening: l10n.scriptGroupHardening,
      ScriptGroup.monitoring: l10n.scriptGroupMonitoring,
      ScriptGroup.peers: l10n.scriptGroupPeers,
    };
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        children: [
          Text(l10n.scriptEditorChooseFile, style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          for (final group in order)
            if (paths.any((p) => scriptGroupFor(p) == group)) ...[
              Padding(
                padding: const EdgeInsets.only(
                  top: AppSpacing.md,
                  bottom: AppSpacing.xs,
                ),
                child: Text(
                  labels[group]!,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              for (final path in paths.where(
                (p) => scriptGroupFor(p) == group,
              ))
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  selected: path == selected,
                  title: Text(
                    path,
                    style: const TextStyle(
                      fontFamily: kMonospacePrimaryFont,
                      fontFamilyFallback: kMonospaceFontFallback,
                      fontSize: 13,
                    ),
                  ),
                  trailing: overridden.contains(path)
                      ? Icon(
                          Icons.edit_outlined,
                          size: 16,
                          color: theme.colorScheme.onSurfaceVariant,
                        )
                      : null,
                  onTap: () => Navigator.of(context).pop(path),
                ),
            ],
        ],
      ),
    );
  }
}

/// A line-by-line diff of the current script against the original (spec §8.5).
class _DiffView extends StatelessWidget {
  const _DiffView({required this.original, required this.modified});

  /// The bundled original script.
  final String original;

  /// The script content currently in the editor.
  final String modified;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final semantic = context.semantic;
    final diff = computeLineDiff(original, modified);
    final changed = diff.any((line) => line.type != DiffLineType.unchanged);
    if (!changed) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Text(
            l10n.scriptEditorNoDiff,
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
        ),
      );
    }
    return ColoredBox(
      color: scheme.surfaceContainerHighest,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        itemCount: diff.length,
        itemBuilder: (context, index) {
          final line = diff[index];
          final (
            Color background,
            Color foreground,
            String prefix,
          ) = switch (line.type) {
            DiffLineType.added => (
              semantic.successSurface,
              semantic.success,
              '+',
            ),
            DiffLineType.removed => (
              scheme.errorContainer,
              scheme.error,
              '-',
            ),
            DiffLineType.unchanged => (
              Colors.transparent,
              scheme.onSurfaceVariant,
              ' ',
            ),
          };
          return Container(
            width: double.infinity,
            color: background,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: 1,
            ),
            child: Text(
              '$prefix ${line.text}',
              style: TextStyle(
                fontFamily: kMonospacePrimaryFont,
                fontFamilyFallback: kMonospaceFontFallback,
                fontSize: 13,
                height: 1.4,
                color: foreground,
              ),
            ),
          );
        },
      ),
    );
  }
}
