import 'dart:async';

import 'package:fav/core/errors/app_exception.dart';
import 'package:fav/core/errors/error_messages.dart';
import 'package:fav/core/router/app_router.dart';
import 'package:fav/core/theme/app_dimens.dart';
import 'package:fav/core/widgets/code_block.dart';
import 'package:fav/features/servers/application/server_teardown_controller.dart';
import 'package:fav/features/servers/application/teardown_guard.dart';
import 'package:fav/features/servers/domain/server.dart';
import 'package:fav/features/servers/presentation/widgets/password_prompt_dialog.dart';
import 'package:fav/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Opens the teardown modal for [server]. The modal owns the whole removal
/// flow (options → optional remote teardown → local removal), so callers do
/// not call `delete` themselves.
Future<void> showTeardownModal(BuildContext context, Server server) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _TeardownModal(server: server),
  );
}

class _TeardownModal extends ConsumerStatefulWidget {
  const _TeardownModal({required this.server});
  final Server server;

  @override
  ConsumerState<_TeardownModal> createState() => _TeardownModalState();
}

class _TeardownModalState extends ConsumerState<_TeardownModal> {
  bool _removeServices = false;
  bool _reopenSsh = false;
  bool _isLaunching = false;

  @override
  void initState() {
    super.initState();
    // Start from a clean state even if a previous teardown left the global
    // notifier in done/failed.
    unawaited(
      Future.microtask(
        () => ref.invalidate(serverTeardownControllerProvider),
      ),
    );
  }

  Server get _server => widget.server;

  bool get _lockoutRisk =>
      teardownWouldLockOut(server: _server, reopenSsh: _reopenSsh);

  Future<void> _confirmLocalRemoval() async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.serverRemoveTitle),
        content: Text(l10n.serverRemoveMessage(_server.label)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.teardownRemoveLocallyConfirmAction),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await ref
        .read(serverTeardownControllerProvider.notifier)
        .removeLocally(_server);
  }

  Future<void> _confirm() async {
    final l10n = AppLocalizations.of(context)!;
    final password = await showPasswordPrompt(
      context,
      l10n.teardownPasswordPromptTarget,
    );
    if (password == null || !mounted) return;
    setState(() => _isLaunching = true);
    try {
      await ref
          .read(serverTeardownControllerProvider.notifier)
          .teardown(
            server: _server,
            removeServices: _removeServices,
            reopenSsh: _reopenSsh,
            password: password,
          );
    } finally {
      if (mounted) setState(() => _isLaunching = false);
    }
    // Reaching TeardownDone closes the modal + shows the snackbar via the
    // single handler in build()'s ref.listen — used by the first attempt, the
    // retry path and remove-locally alike. Popping here too would double-pop
    // the navigator (a `!_debugLocked` assertion during dispose).
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(serverTeardownControllerProvider);

    // Single place that closes the modal + shows the snackbar when the
    // teardown succeeds (first attempt, retry, or remove-locally). Deferred to
    // after the frame so the pop never runs while the navigator is locked
    // mid-build/dispose (a `!_debugLocked` assertion).
    ref.listen(serverTeardownControllerProvider, (_, next) {
      if (next is! TeardownDone) return;
      final navigator = Navigator.of(context);
      final messenger = ScaffoldMessenger.of(context);
      final label = _server.label;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (navigator.canPop()) navigator.pop();
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.teardownDoneSnackbar(label))),
        );
      });
    });

    return AlertDialog(
      title: Text(l10n.teardownTitle),
      content:
          _isLaunching && (state is TeardownIdle || state is TeardownFailure)
          ? _LaunchingView(l10n: l10n)
          : switch (state) {
              TeardownReopeningSsh() ||
              TeardownRunningServices() ||
              TeardownRemovingAppKey() => _ProgressView(
                state: state,
                l10n: l10n,
              ),
              TeardownFailure(:final error) => _FailureView(
                error: error,
                l10n: l10n,
              ),
              // TeardownIdle and TeardownLockoutRisk both render the options
              // view. TeardownLockoutRisk is handled here (rather than as a
              // separate branch that blocks _confirm()) because the
              // _lockoutRisk guard already prevents a risky teardown. The
              // controller state is a defensive signal, not the gate.
              _ => _OptionsView(
                server: _server,
                l10n: l10n,
                removeServices: _removeServices,
                reopenSsh: _reopenSsh,
                lockoutRisk: _lockoutRisk,
                onServicesChanged: (v) => setState(() => _removeServices = v),
                onReopenChanged: (v) => setState(() => _reopenSsh = v),
              ),
            },
      actions: _isLaunching ? const [] : _actionsFor(state, l10n),
    );
  }

  List<Widget> _actionsFor(TeardownFlowState state, AppLocalizations l10n) {
    switch (state) {
      case TeardownReopeningSsh():
      case TeardownRunningServices():
      case TeardownRemovingAppKey():
        return const []; // no actions while running
      case TeardownFailure():
        return [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.actionCancel),
          ),
          TextButton(
            onPressed: () => unawaited(_confirmLocalRemoval()),
            child: Text(l10n.teardownRemoveLocallyAction),
          ),
          FilledButton(
            onPressed: _confirm,
            child: Text(l10n.teardownRetryAction),
          ),
        ];
      // TeardownIdle and TeardownLockoutRisk both render the options actions.
      // TeardownLockoutRisk is handled here because the _lockoutRisk guard
      // prevents _confirm() from launching a risky teardown; the controller
      // state is defensive only — the widget's own check is the gate.
      default:
        return [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.actionCancel),
          ),
          if (!_removeServices && !_reopenSsh)
            TextButton(
              onPressed: () => unawaited(_confirmLocalRemoval()),
              child: Text(l10n.teardownRemoveLocallyAction),
            ),
          if (_lockoutRisk)
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                context.go(serverDetailPath(_server.id));
              },
              child: Text(l10n.teardownAddKeyAction),
            )
          else
            FilledButton(
              onPressed: _confirm,
              child: Text(
                _removeServices
                    ? l10n.teardownUninstallAction
                    : l10n.teardownDisconnectAction,
              ),
            ),
        ];
    }
  }
}

class _LaunchingView extends StatelessWidget {
  const _LaunchingView({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      const SizedBox(width: AppSpacing.md),
      Flexible(child: Text(l10n.teardownProgressServices)),
    ],
  );
}

class _OptionsView extends StatelessWidget {
  const _OptionsView({
    required this.server,
    required this.l10n,
    required this.removeServices,
    required this.reopenSsh,
    required this.lockoutRisk,
    required this.onServicesChanged,
    required this.onReopenChanged,
  });

  final Server server;
  final AppLocalizations l10n;
  final bool removeServices;
  final bool reopenSsh;
  final bool lockoutRisk;
  final ValueChanged<bool> onServicesChanged;
  final ValueChanged<bool> onReopenChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.teardownMessage(server.label)),
          const SizedBox(height: AppSpacing.md),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: removeServices,
            onChanged: (v) => onServicesChanged(v ?? false),
            title: Text(l10n.teardownServicesOption),
            subtitle: Text(l10n.teardownServicesHint),
          ),
          // Re-opening SSH only makes sense when the app actually changed
          // SSH access — hardening (password auth off) or the anti-lockout
          // sequence (root login off). On an untouched server the option is
          // noise (audit F8; root-SSH case from security review L4).
          if ((server.installation?.hardeningApplied ?? false) ||
              (server.installation?.rootSshDisabled ?? false))
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: reopenSsh,
              onChanged: (v) => onReopenChanged(v ?? false),
              title: Text(l10n.teardownReopenOption),
              subtitle: Text(
                l10n.teardownReopenWarning,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          const SizedBox(height: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(AppRadii.card),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline,
                  size: 20,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    removeServices
                        ? l10n.teardownUninstallSummary
                        : l10n.teardownDisconnectSummary,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (lockoutRisk) ...[
            const SizedBox(height: AppSpacing.sm),
            Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(AppRadii.card),
              ),
              child: Text(
                l10n.teardownLockoutWarning,
                style: TextStyle(color: theme.colorScheme.onErrorContainer),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ProgressView extends StatelessWidget {
  const _ProgressView({required this.state, required this.l10n});
  final TeardownFlowState state;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final label = switch (state) {
      TeardownReopeningSsh() => l10n.teardownProgressReopening,
      TeardownRunningServices() => l10n.teardownProgressServices,
      TeardownRemovingAppKey() => l10n.teardownProgressRemovingKey,
      _ => throw StateError('_ProgressView used with a non-progress state'),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: AppSpacing.md),
        Flexible(child: Text(label)),
      ],
    );
  }
}

class _FailureView extends StatelessWidget {
  const _FailureView({required this.error, required this.l10n});
  final AppException error;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.teardownFailedTitle,
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(localizedErrorMessage(l10n, error.code)),
        if (error.detail != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Theme(
            // Drop the default ExpansionTile divider lines to honour the flat,
            // hairline-only elevation model.
            data: theme.copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: AppSpacing.sm),
              expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
              title: Text(
                l10n.errorTechnicalDetails,
                style: theme.textTheme.titleSmall,
              ),
              children: [CodeBlock(content: error.detail!)],
            ),
          ),
        ],
      ],
    );
  }
}
