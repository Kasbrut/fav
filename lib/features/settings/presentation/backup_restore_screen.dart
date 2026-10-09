import 'dart:async';

import 'package:fav/core/router/app_router.dart';
import 'package:fav/core/theme/app_dimens.dart';
import 'package:fav/core/widgets/app_card.dart';
import 'package:fav/core/widgets/app_text_field.dart';
import 'package:fav/core/widgets/responsive_app_bar.dart';
import 'package:fav/core/widgets/section_header.dart';
import 'package:fav/features/servers/application/server_list_controller.dart';
import 'package:fav/features/servers/data/hive_server_repository.dart';
import 'package:fav/features/servers/domain/server.dart';
import 'package:fav/features/servers/presentation/widgets/password_prompt_dialog.dart';
import 'package:fav/features/settings/application/backup_service.dart';
import 'package:fav/features/settings/application/preferences_controller.dart';
import 'package:fav/features/settings/application/restore_server_service.dart';
import 'package:fav/l10n/app_localizations.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

/// Creates encrypted backups and restores them into an empty installation.
class BackupRestoreScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const BackupRestoreScreen({super.key});

  @override
  ConsumerState<BackupRestoreScreen> createState() =>
      _BackupRestoreScreenState();
}

class _BackupRestoreScreenState extends ConsumerState<BackupRestoreScreen> {
  bool _busy = false;
  bool _pendingLoaded = false;
  String? _status;
  PendingRestore? _pendingRestore;
  List<Server> _pendingServers = const [];

  @override
  void initState() {
    super.initState();
    unawaited(Future<void>.microtask(_refreshPendingState));
  }

  Future<void> _refreshPendingState() async {
    final service = ref.read(backupServiceProvider);
    var pending = service.pendingRestore;
    var servers = const <Server>[];
    if (pending != null) {
      final allServers = await ref.read(serverRepositoryProvider).getAll();
      final existingIds = allServers.map((server) => server.id).toSet();
      for (final missingId in pending.serverIds.where(
        (id) => !existingIds.contains(id),
      )) {
        await service.completeOnlineRestoreFor(missingId);
      }
      pending = service.pendingRestore;
      if (pending != null) {
        final pendingIds = pending.serverIds.toSet();
        servers = allServers
            .where((server) => pendingIds.contains(server.id))
            .toList();
      }
    }
    if (!mounted) return;
    setState(() {
      _pendingRestore = pending;
      _pendingServers = servers;
      _pendingLoaded = true;
    });
  }

  Future<void> _createBackup() async {
    final l10n = AppLocalizations.of(context)!;
    final password = await _showBackupPasswordDialog(confirm: true);
    if (password == null || !mounted) return;
    setState(() {
      _busy = true;
      _status = l10n.backupCreating;
    });
    try {
      final service = ref.read(backupServiceProvider);
      final summary = await service.summarizeCurrentData();
      final bytes = await service.create(password);
      final date = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final uri = await FilePicker.saveFile(
        fileName: 'fav-backup-$date.favbackup',
        bytes: bytes,
        dialogTitle: l10n.backupSaveDialogTitle,
      );
      if (!mounted) return;
      setState(() => _status = null);
      if (uri != null) {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(l10n.backupCreated),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.backupRestoreSummary(
                      summary.serverCount,
                      summary.peerCount,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(l10n.backupCreateBody),
                ],
              ),
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l10n.actionDone),
              ),
            ],
          ),
        );
      }
    } on Object {
      if (mounted) setState(() => _status = l10n.backupCreateFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restoreBackup() async {
    final l10n = AppLocalizations.of(context)!;
    final picked = await FilePicker.pickFile(
      dialogTitle: l10n.backupChooseDialogTitle,
      type: FileType.custom,
      allowedExtensions: const ['favbackup'],
    );
    if (picked == null || !mounted) return;
    final bytes = await picked.readAsBytes();
    final password = await _showBackupPasswordDialog(confirm: false);
    if (password == null || !mounted) return;

    setState(() {
      _busy = true;
      _status = l10n.backupReading;
    });
    try {
      final service = ref.read(backupServiceProvider);
      final summary = await service.inspect(bytes, password);
      if (!mounted) return;
      final options = await showDialog<_RestoreOptions>(
        context: context,
        barrierDismissible: false,
        builder: (context) => _RestoreOptionsDialog(summary: summary),
      );
      if (options == null || !mounted) {
        if (mounted) setState(() => _status = null);
        return;
      }
      setState(() => _status = l10n.backupRestoring);
      await service.restore(
        bytes,
        password,
        rotateSshKeys: options.rotateSshKeys,
        revokePeers: options.revokePeers,
      );
      ref
        ..invalidate(preferencesControllerProvider)
        ..invalidate(serverListControllerProvider);
      final servers = await ref.read(serverRepositoryProvider).getAll();
      final outcomes = await _verifyServers(servers, options);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l10n.backupRestoreResultTitle),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SingleChildScrollView(child: Text(outcomes.join('\n'))),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.actionDone),
            ),
          ],
        ),
      );
      if (mounted) context.go(serverListRoute);
    } on Object {
      if (mounted) setState(() => _status = l10n.backupRestoreFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resumeRestore() async {
    await _refreshPendingState();
    final service = ref.read(backupServiceProvider);
    final pending = service.pendingRestore;
    final servers = _pendingServers;
    if (pending == null || servers.isEmpty) {
      if (mounted) setState(() => _status = null);
      return;
    }
    setState(() {
      _busy = true;
      _status = AppLocalizations.of(context)!.backupReading;
    });
    try {
      final outcomes = await _verifyServers(
        servers,
        _RestoreOptions(
          rotateSshKeys: pending.rotateSshKeys,
          revokePeers: pending.revokePeers,
        ),
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(AppLocalizations.of(context)!.backupRestoreResultTitle),
          content: Text(outcomes.join('\n')),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(AppLocalizations.of(context)!.actionDone),
            ),
          ],
        ),
      );
      await _refreshPendingState();
      if (mounted) setState(() => _status = null);
    } on Object {
      if (mounted) {
        setState(
          () => _status = AppLocalizations.of(context)!.backupRestoreFailed,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<List<String>> _verifyServers(
    List<Server> servers,
    _RestoreOptions options,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final operations = ref.read(restoreServerServiceProvider);
    final outcomes = <String>[];
    for (var index = 0; index < servers.length; index++) {
      final server = servers[index];
      if (!mounted) break;
      setState(
        () => _status = l10n.backupVerifyingServer(
          server.label,
          index + 1,
          servers.length,
        ),
      );
      String? password;
      final needsLoginPassword = server.sshKeyId == null;
      final needsSudoPassword =
          options.revokePeers && server.username != 'root';
      if (needsLoginPassword || needsSudoPassword) {
        password = await showPasswordPrompt(context, server.label);
        if (password == null) {
          outcomes.add(l10n.backupServerPending(server.label));
          continue;
        }
      }
      try {
        await operations.verify(server, password: password);
        if (options.rotateSshKeys) {
          await operations.rotateFavourKey(server);
        }
        if (options.revokePeers) {
          await operations.revokeRestoredPeers(
            server,
            sudoPassword: password ?? '',
          );
        }
        outcomes.add(l10n.backupServerVerified(server.label));
        await ref
            .read(backupServiceProvider)
            .completeOnlineRestoreFor(server.id);
      } on Object {
        outcomes.add(l10n.backupServerPending(server.label));
      }
    }
    await ref.read(serverListControllerProvider.notifier).refresh();
    return outcomes;
  }

  Future<String?> _showBackupPasswordDialog({required bool confirm}) {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _BackupPasswordDialog(confirm: confirm),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cannotRestore = ref.read(backupServiceProvider).hasRestorableData;
    final pendingRestore = _pendingRestore;
    return Scaffold(
      appBar: ResponsiveAppBar(
        title: l10n.backupTitle,
        maxContentWidth: AppSizes.contentMaxWidth,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppSizes.contentMaxWidth),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.xxl,
            ),
            children: [
              SectionHeader(label: l10n.backupCreateSection),
              const SizedBox(height: AppSpacing.sm),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.backupCreateBody),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      l10n.backupMultiDeviceWarning,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    FilledButton.icon(
                      onPressed: _busy ? null : _createBackup,
                      icon: const Icon(Icons.lock_outline),
                      label: Text(l10n.backupCreateAction),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              SectionHeader(label: l10n.backupRestoreSection),
              const SizedBox(height: AppSpacing.sm),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.backupRestoreBody),
                    const SizedBox(height: AppSpacing.md),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.wifi_outlined,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(child: Text(l10n.backupInternetWarning)),
                      ],
                    ),
                    if (_pendingLoaded &&
                        cannotRestore &&
                        pendingRestore == null) ...[
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        l10n.backupEmptyAppRequired,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.lg),
                    if (!_pendingLoaded)
                      const Center(child: CircularProgressIndicator())
                    else if (pendingRestore == null)
                      OutlinedButton.icon(
                        onPressed: _busy || cannotRestore
                            ? null
                            : _restoreBackup,
                        icon: const Icon(Icons.restore_outlined),
                        label: Text(l10n.backupRestoreAction),
                      )
                    else ...[
                      Text(
                        l10n.backupPendingServersTitle,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      ..._pendingServers.map(
                        (server) => Padding(
                          padding: const EdgeInsets.only(
                            bottom: AppSpacing.xs,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.schedule_outlined,
                                size: 20,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(child: Text(server.label)),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      FilledButton.icon(
                        onPressed: _busy ? null : _resumeRestore,
                        icon: const Icon(Icons.sync_outlined),
                        label: Text(l10n.backupResumeAction),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(l10n.backupResumeBody),
                    ],
                  ],
                ),
              ),
              if (_busy || _status != null) ...[
                const SizedBox(height: AppSpacing.lg),
                Semantics(
                  liveRegion: true,
                  child: Row(
                    children: [
                      if (_busy) ...[
                        const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                      ],
                      if (_status != null) Expanded(child: Text(_status!)),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _BackupPasswordDialog extends StatefulWidget {
  const _BackupPasswordDialog({required this.confirm});

  final bool confirm;

  @override
  State<_BackupPasswordDialog> createState() => _BackupPasswordDialogState();
}

class _BackupPasswordDialogState extends State<_BackupPasswordDialog> {
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  String? _error;

  void _validateLive() {
    final l10n = AppLocalizations.of(context)!;
    String? error;
    if (_password.text.isNotEmpty && _password.text.length < 12) {
      error = l10n.backupPasswordTooShort;
    } else if (widget.confirm &&
        _confirmation.text.isNotEmpty &&
        _password.text != _confirmation.text) {
      error = l10n.backupPasswordMismatch;
    }
    if (_error != error) setState(() => _error = error);
  }

  @override
  void dispose() {
    _password
      ..clear()
      ..dispose();
    _confirmation
      ..clear()
      ..dispose();
    super.dispose();
  }

  void _submit() {
    final l10n = AppLocalizations.of(context)!;
    if (_password.text.length < 12) {
      setState(() => _error = l10n.backupPasswordTooShort);
      return;
    }
    if (widget.confirm && _password.text != _confirmation.text) {
      setState(() => _error = l10n.backupPasswordMismatch);
      return;
    }
    Navigator.of(context).pop(_password.text);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(
        widget.confirm
            ? l10n.backupPasswordCreateTitle
            : l10n.backupPasswordTitle,
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.confirm
                  ? l10n.backupPasswordBody
                  : l10n.backupPasswordUnlockBody,
            ),
            const SizedBox(height: AppSpacing.lg),
            AppTextField(
              label: l10n.fieldPassword,
              controller: _password,
              obscureText: true,
              autofocus: true,
              onChanged: (_) => _validateLive(),
            ),
            if (widget.confirm) ...[
              const SizedBox(height: AppSpacing.md),
              AppTextField(
                label: l10n.backupPasswordConfirm,
                controller: _confirmation,
                obscureText: true,
                onChanged: (_) => _validateLive(),
                onFieldSubmitted: (_) => _submit(),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.actionCancel),
        ),
        FilledButton(onPressed: _submit, child: Text(l10n.actionContinue)),
      ],
    );
  }
}

class _RestoreOptions {
  const _RestoreOptions({
    required this.rotateSshKeys,
    required this.revokePeers,
  });

  final bool rotateSshKeys;
  final bool revokePeers;
}

class _RestoreOptionsDialog extends StatefulWidget {
  const _RestoreOptionsDialog({required this.summary});

  final BackupSummary summary;

  @override
  State<_RestoreOptionsDialog> createState() => _RestoreOptionsDialogState();
}

class _RestoreOptionsDialogState extends State<_RestoreOptionsDialog> {
  bool _rotate = false;
  bool _revoke = false;

  Future<void> _selectRevoke(bool selected) async {
    if (!selected) {
      setState(() => _revoke = false);
      return;
    }
    final l10n = AppLocalizations.of(context)!;
    final first = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.backupRevokeConfirmTitle),
        content: Text(l10n.backupRevokeConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.actionContinue),
          ),
        ],
      ),
    );
    if (first != true || !mounted) return;
    final controller = TextEditingController();
    final second = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(l10n.backupRevokeFinalTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.backupRevokeFinalBody(l10n.backupRevokeWord)),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: controller,
                autofocus: true,
                onChanged: (_) => setDialogState(() {}),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.actionCancel),
            ),
            FilledButton(
              onPressed: controller.text.trim() == l10n.backupRevokeWord
                  ? () => Navigator.of(context).pop(true)
                  : null,
              child: Text(l10n.backupRevokeAction),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (second == true && mounted) setState(() => _revoke = true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l10n.backupRestoreConfirmTitle),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(AppRadii.card),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.inventory_2_outlined,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Text(
                        l10n.backupRestoreSummary(
                          widget.summary.serverCount,
                          widget.summary.peerCount,
                        ),
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(l10n.backupMultiDeviceWarning),
              const SizedBox(height: AppSpacing.md),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.wifi_outlined,
                    size: 20,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      l10n.backupInternetWarning,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              const Divider(),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _rotate,
                onChanged: (value) => setState(() => _rotate = value),
                title: Text(l10n.backupRotateKeysTitle),
                subtitle: Text(l10n.backupRotateKeysBody),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                decoration: BoxDecoration(
                  color: _revoke
                      ? Theme.of(
                          context,
                        ).colorScheme.errorContainer.withValues(alpha: 0.45)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppRadii.card),
                ),
                child: CheckboxListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                  ),
                  value: _revoke,
                  onChanged: (value) => _selectRevoke(value ?? false),
                  secondary: Icon(
                    Icons.warning_amber_rounded,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  title: Text(
                    l10n.backupRevokePeersTitle,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(l10n.backupRevokePeersBody),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.actionCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(
            _RestoreOptions(rotateSshKeys: _rotate, revokePeers: _revoke),
          ),
          child: Text(l10n.backupRestoreAction),
        ),
      ],
    );
  }
}
