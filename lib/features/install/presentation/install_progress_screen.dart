import 'dart:async';

import 'package:fav/core/errors/error_messages.dart';
import 'package:fav/core/router/app_router.dart';
import 'package:fav/core/theme/app_dimens.dart';
import 'package:fav/core/theme/app_semantic_colors.dart';
import 'package:fav/core/utils/log_scrubber.dart';
import 'package:fav/core/widgets/app_banner.dart';
import 'package:fav/core/widgets/code_block.dart';
import 'package:fav/core/widgets/install_step_tile.dart';
import 'package:fav/core/widgets/monospace_text.dart';
import 'package:fav/core/widgets/primary_button.dart';
import 'package:fav/core/widgets/secondary_button.dart';
import 'package:fav/features/help/application/recent_errors_provider.dart';
import 'package:fav/features/help/presentation/error_help_link.dart';
import 'package:fav/features/install/application/install_controller.dart';
import 'package:fav/features/install/application/run_polling_controller.dart';
import 'package:fav/features/install/domain/install_run.dart';
import 'package:fav/features/install/domain/install_step.dart';
import 'package:fav/features/install/presentation/install_step_labels.dart';
import 'package:fav/features/servers/application/server_list_controller.dart';
import 'package:fav/features/servers/domain/server.dart';
import 'package:fav/features/settings/application/preferences_controller.dart';
import 'package:fav/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

/// Shows the progress of a detached installation run (spec §9.1).
class InstallProgressScreen extends ConsumerWidget {
  /// Creates the install progress screen.
  const InstallProgressScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final state = ref.watch(installControllerProvider);
    ref.listen(installControllerProvider, (previous, next) {
      if (next is InstallNeedsConfirmation) {
        unawaited(_showReinstallDialog(context, ref, next.server, l10n));
      } else if (next is InstallFailure) {
        // Record the failure exactly once, on the transition into the failed
        // state, rather than on every rebuild of the failure view. Every path
        // to this screen (fresh install, recovered run) reaches failure while
        // the screen is mounted, so the transition is always observed here.
        ref.read(recentErrorsProvider.notifier).record(next.error.code);
        unawaited(
          ref
              .read(preferencesControllerProvider.notifier)
              .recordError(next.error.code.id, DateTime.now()),
        );
      }
    });
    final run = switch (state) {
      InstallRunning(:final run) => run,
      InstallAntiLockout(:final run) => run,
      InstallHardening(:final run) => run,
      InstallSuccess(:final run) => run,
      InstallFailure(:final run) => run,
      _ => null,
    };
    final subtitle = run == null ? null : _runSubtitle(ref, l10n, run);
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.installProgressTitle),
            if (subtitle != null)
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
      body: SafeArea(
        child: switch (state) {
          InstallIdle() ||
          InstallPreparing() ||
          InstallNeedsConfirmation() => _PreparingView(l10n: l10n),
          InstallRunning(:final run) => _RunningView(run: run, l10n: l10n),
          InstallAntiLockout(:final run) => _RunningView(
            run: run,
            l10n: l10n,
            antiLockout: true,
          ),
          InstallHardening(:final run) => _RunningView(
            run: run,
            l10n: l10n,
            hardening: true,
          ),
          InstallSuccess() => _SuccessView(state: state, l10n: l10n),
          InstallFailure() => _FailureView(state: state, l10n: l10n),
        },
      ),
    );
  }

  /// Builds the app-bar subtitle (`server name · run id`) for a run.
  String _runSubtitle(WidgetRef ref, AppLocalizations l10n, InstallRun run) {
    final servers =
        ref.watch(serverListControllerProvider).value ?? const <Server>[];
    final matches = servers.where((server) => server.id == run.serverId);
    final shortId = run.runId.length >= 6
        ? run.runId.substring(0, 6)
        : run.runId;
    final runRef = l10n.installRunReference(shortId);
    return matches.isEmpty ? runRef : '${matches.first.label} · $runRef';
  }

  Future<void> _showReinstallDialog(
    BuildContext context,
    WidgetRef ref,
    Server server,
    AppLocalizations l10n,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(l10n.secondInstallTitle),
        content: Text(l10n.secondInstallMessage(server.label)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.actionReinstall),
          ),
        ],
      ),
    );
    final controller = ref.read(installControllerProvider.notifier);
    if (confirmed ?? false) {
      await controller.confirmReinstall();
    } else {
      controller.cancel();
      if (context.mounted) {
        context.go(serverListRoute);
      }
    }
  }
}

/// Opens the full installation log in a bottom sheet with copy and share
/// actions, so a non-technical user can hand the log to someone who can help.
Future<void> _showRunLog(BuildContext context, WidgetRef ref) async {
  final l10n = AppLocalizations.of(context)!;
  final messenger = ScaffoldMessenger.of(context);
  final log = await ref.read(installControllerProvider.notifier).fetchRunLog();
  if (!context.mounted) {
    return;
  }
  final hasLog = log.isNotEmpty;
  final content = hasLog ? log : '—';
  // What leaves the device (clipboard, share sheet) holds the same bar as
  // the bug-report scrubber — usernames, IPs, hostnames, fingerprints
  // masked. The sheet itself stays verbatim: it is an on-device diagnostic
  // (audit L6).
  final exported = hasLog ? scrubLog(log.split('\n')) : content;
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) {
      final theme = Theme.of(context);
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            0,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.runLogTitle,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    tooltip: l10n.actionCopy,
                    icon: const Icon(Icons.copy_outlined),
                    onPressed: hasLog
                        ? () async {
                            await Clipboard.setData(
                              ClipboardData(text: exported),
                            );
                            messenger.showSnackBar(
                              SnackBar(content: Text(l10n.logCopied)),
                            );
                          }
                        : null,
                  ),
                  IconButton(
                    tooltip: l10n.actionShare,
                    icon: const Icon(Icons.ios_share),
                    onPressed: hasLog
                        ? () => unawaited(
                            SharePlus.instance.share(
                              ShareParams(
                                text: exported,
                                subject: l10n.runLogTitle,
                                sharePositionOrigin:
                                    (context.findRenderObject()! as RenderBox)
                                        .localToGlobal(Offset.zero) &
                                    (context.findRenderObject()! as RenderBox)
                                        .size,
                              ),
                            ),
                          )
                        : null,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Flexible(
                child: SingleChildScrollView(
                  child: CodeBlock(content: content),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// Formats a run duration as `M:SS`.
String _formatElapsed(Duration elapsed) {
  final minutes = elapsed.inMinutes;
  final seconds = elapsed.inSeconds % 60;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

/// Formats a step duration compactly (seconds, or whole minutes past 60 s).
String _formatStepDuration(AppLocalizations l10n, Duration duration) {
  final seconds = duration.inSeconds;
  return seconds < 60
      ? l10n.stepDurationSeconds(seconds)
      : l10n.stepDurationMinutes(duration.inMinutes);
}

class _PreparingView extends StatelessWidget {
  const _PreparingView({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: AppSpacing.lg),
          Text(l10n.installPreparing),
        ],
      ),
    );
  }
}

class _RunningView extends ConsumerStatefulWidget {
  const _RunningView({
    required this.run,
    required this.l10n,
    this.antiLockout = false,
    this.hardening = false,
  });

  final InstallRun run;
  final AppLocalizations l10n;
  final bool antiLockout;
  final bool hardening;

  @override
  ConsumerState<_RunningView> createState() => _RunningViewState();
}

class _RunningViewState extends ConsumerState<_RunningView> {
  bool _isCancelling = false;

  @override
  Widget build(BuildContext context) {
    final run = widget.run;
    final l10n = widget.l10n;
    final polling = ref.watch(runPollingControllerProvider);
    final liveRun = polling.run ?? run;
    final steps = liveRun.steps;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.xxl,
      ),
      children: [
        if (polling.connectionLost) ...[
          AppBanner(
            variant: AppBannerVariant.warning,
            icon: Icons.wifi_off,
            message: l10n.runConnectionLost,
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        if (liveRun.scriptWasModified) ...[
          AppBanner(
            variant: AppBannerVariant.warning,
            icon: Icons.warning_amber,
            message: l10n.scriptModifiedBanner,
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        if (widget.antiLockout) ...[
          AppBanner(icon: Icons.lock, message: l10n.antiLockoutInProgress),
          const SizedBox(height: AppSpacing.sm),
        ],
        if (widget.hardening) ...[
          AppBanner(icon: Icons.shield, message: l10n.hardeningInProgress),
          const SizedBox(height: AppSpacing.sm),
        ],
        _ProgressHeader(run: liveRun, l10n: l10n),
        const SizedBox(height: AppSpacing.lg),
        for (var i = 0; i < steps.length; i++)
          _StepTile(
            step: steps[i],
            l10n: l10n,
            isFirst: i == 0,
            isLast: i == steps.length - 1,
            position: i + 1,
          ),
        const SizedBox(height: AppSpacing.lg),
        _RunDetails(
          hash: liveRun.scriptContentHash,
          l10n: l10n,
          onViewLog: () => _showRunLog(context, ref),
        ),
        const SizedBox(height: AppSpacing.lg),
        SecondaryButton(
          label: l10n.actionCancel,
          icon: Icons.cancel,
          isLoading: _isCancelling,
          onPressed: () {
            if (_isCancelling) return;
            setState(() => _isCancelling = true);
            ref.read(installControllerProvider.notifier).cancel();
          },
        ),
      ],
    );
  }
}

/// The step count, elapsed time and progress bar shown above the step list.
class _ProgressHeader extends StatelessWidget {
  const _ProgressHeader({required this.run, required this.l10n});

  final InstallRun run;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final steps = run.steps;
    final total = steps.length;
    final completed = steps
        .where(
          (step) =>
              step.status == StepStatus.done ||
              step.status == StepStatus.skipped,
        )
        .length;
    final running = steps.any((step) => step.status == StepStatus.running);
    final current = total == 0
        ? 0
        : (completed + (running ? 1 : 0)).clamp(1, total);
    final elapsed = DateTime.now().difference(run.startedAt);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.installProgressHeader(current, total, _formatElapsed(elapsed)),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadii.badge),
          child: LinearProgressIndicator(
            value: total == 0 ? null : completed / total,
            minHeight: 6,
          ),
        ),
      ],
    );
  }
}

class _StepTile extends StatelessWidget {
  const _StepTile({
    required this.step,
    required this.l10n,
    required this.isFirst,
    required this.isLast,
    required this.position,
  });

  final InstallStep step;
  final AppLocalizations l10n;
  final bool isFirst;
  final bool isLast;
  final int position;

  @override
  Widget build(BuildContext context) {
    final status = switch (step.status) {
      StepStatus.pending => InstallStepStatusView.pending,
      StepStatus.running => InstallStepStatusView.running,
      StepStatus.done => InstallStepStatusView.done,
      StepStatus.error => InstallStepStatusView.error,
      StepStatus.skipped => InstallStepStatusView.skipped,
    };
    final startedAt = step.startedAt;
    final completedAt = step.completedAt;
    String? trailing;
    if (step.status == StepStatus.running) {
      trailing = l10n.stepInProgress;
    } else if (step.status == StepStatus.done &&
        startedAt != null &&
        completedAt != null) {
      trailing = _formatStepDuration(l10n, completedAt.difference(startedAt));
    }
    final name = installStepLabel(l10n, step.key);
    final statusText = switch (step.status) {
      StepStatus.pending => l10n.stepStatusPending,
      StepStatus.running => l10n.stepStatusRunning,
      StepStatus.done => l10n.stepStatusDone,
      StepStatus.error => l10n.stepStatusError,
      StepStatus.skipped => l10n.stepStatusSkipped,
    };
    // One screen-reader phrase per step: name + status, plus the failure
    // detail when present, so the timeline's state is perceivable without
    // relying on the icon shape alone.
    final detail = step.errorMessage;
    final semanticLabel = detail == null
        ? l10n.installStepSemantic(name, statusText)
        : '${l10n.installStepSemantic(name, statusText)}. $detail';
    return InstallStepTile(
      name: name,
      status: status,
      detail: detail,
      trailing: trailing,
      position: position,
      isFirst: isFirst,
      isLast: isLast,
      semanticLabel: semanticLabel,
    );
  }
}

/// Diagnostic run metadata (script hash + full log), tucked behind a
/// disclosure so the running screen stays calm. The script-modified warning
/// stays outside this section: it is a security signal, not a detail.
class _RunDetails extends StatelessWidget {
  const _RunDetails({
    required this.hash,
    required this.l10n,
    required this.onViewLog,
  });

  final String? hash;
  final AppLocalizations l10n;
  final VoidCallback onViewLog;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Theme(
      // Drop the default ExpansionTile divider lines to honour the flat,
      // hairline-only elevation model.
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: AppSpacing.sm),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        title: Text(l10n.runDetailsTitle, style: theme.textTheme.titleSmall),
        children: [
          Text(
            l10n.scriptHashLabel,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          MonospaceText(hash ?? '—'),
          const SizedBox(height: AppSpacing.md),
          SecondaryButton(
            label: l10n.runViewLog,
            icon: Icons.article,
            onPressed: onViewLog,
          ),
        ],
      ),
    );
  }
}

class _SuccessView extends ConsumerWidget {
  const _SuccessView({required this.state, required this.l10n});

  final InstallSuccess state;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final backup = state.configBackupPath;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.xl,
        AppSpacing.xl,
        AppSpacing.xxl,
      ),
      children: [
        Column(
          children: [
            Icon(
              Icons.check_circle,
              color: context.semantic.success,
              size: AppSizes.emptyStateIcon,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              l10n.installSuccessTitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(l10n.installSuccessBody, textAlign: TextAlign.center),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
        // What changed: a scannable summary of the outcomes, not loose
        // centered sentences.
        _OutcomeRow(
          label: backup == null
              ? l10n.configBackupNone
              : l10n.configBackupDone(backup),
          neutral: backup == null,
        ),
        if (state.rootSshDisabled) ...[
          const SizedBox(height: AppSpacing.sm),
          _OutcomeRow(label: l10n.antiLockoutDisabled),
        ],
        if (state.hardeningApplied) ...[
          const SizedBox(height: AppSpacing.sm),
          _OutcomeRow(label: l10n.hardeningApplied),
        ],
        if (state.lockoutWarning != null || state.hardeningWarning != null) ...[
          const SizedBox(height: AppSpacing.lg),
          AppBanner(
            variant: AppBannerVariant.warning,
            icon: Icons.shield_outlined,
            title: l10n.hardeningIncompleteTitle,
            message: [
              if (state.lockoutWarning != null) l10n.antiLockoutWarning,
              if (state.hardeningWarning != null) l10n.hardeningWarning,
            ].join('\n\n'),
          ),
        ],
        const SizedBox(height: AppSpacing.xl),
        PrimaryButton(
          label: l10n.profileViewProfileAction,
          icon: Icons.qr_code_2,
          onPressed: () {
            ref.read(installControllerProvider.notifier).reset();
            context.go(profileResultPath(state.run.serverId));
          },
        ),
        const SizedBox(height: AppSpacing.sm),
        SecondaryButton(
          label: l10n.actionDone,
          onPressed: () {
            ref.read(installControllerProvider.notifier).reset();
            context.go(serverListRoute);
          },
        ),
      ],
    );
  }
}

/// A single "what changed" outcome row: a leading status icon and a label.
/// [neutral] downgrades it from a success check to an informational note
/// (e.g. "no previous configuration was found").
class _OutcomeRow extends StatelessWidget {
  const _OutcomeRow({required this.label, this.neutral = false});

  final String label;
  final bool neutral;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = neutral
        ? theme.colorScheme.onSurfaceVariant
        : context.semantic.success;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          neutral ? Icons.info_outline : Icons.check_circle,
          size: AppSizes.statusIcon,
          color: color,
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
      ],
    );
  }
}

class _FailureView extends ConsumerWidget {
  const _FailureView({required this.state, required this.l10n});

  final InstallFailure state;
  final AppLocalizations l10n;

  Future<void> _cleanup(BuildContext context, WidgetRef ref) async {
    final removed = await ref
        .read(installControllerProvider.notifier)
        .cleanupRun();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(removed ? l10n.cleanupDone : l10n.cleanupFailed),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The failure is recorded once on the state transition (see the
    // installControllerProvider listener), not here in build.
    final theme = Theme.of(context);
    final message = localizedErrorMessage(
      l10n,
      state.error.code,
      stepName: state.failedStepKey,
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.xl,
        AppSpacing.xl,
        AppSpacing.xxl,
      ),
      children: [
        Column(
          children: [
            Icon(
              Icons.error,
              color: theme.colorScheme.error,
              size: AppSizes.emptyStateIcon,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              l10n.installFailedTitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(message, textAlign: TextAlign.center),
            ErrorHelpButton(code: state.error.code),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        // One obvious recovery leads; the escape is clearly secondary.
        PrimaryButton(
          label: l10n.actionRestartInstall,
          onPressed: () {
            final controller = ref.read(installControllerProvider.notifier);
            final retryServer = controller.retryServer;
            controller.reset();
            context.go(addServerRoute, extra: retryServer);
          },
        ),
        const SizedBox(height: AppSpacing.sm),
        // Always offer a way back to the server list — otherwise the failure
        // screen is a dead-end (M14 smoke test 2026-05-21).
        SecondaryButton(
          label: l10n.actionBackToServers,
          onPressed: () {
            ref.read(installControllerProvider.notifier).reset();
            context.go(serverListRoute);
          },
        ),
        const SizedBox(height: AppSpacing.lg),
        // Diagnostics and advanced recovery, grouped out of the main path.
        // No run launched → no remote log to fetch (audit F11); the cleanup
        // stays: server files may exist when the launch failed after staging.
        _TechnicalDetails(
          detail: state.error.detail,
          l10n: l10n,
          onViewLog: state.run == null ? null : () => _showRunLog(context, ref),
          onCleanup: () => _cleanup(context, ref),
        ),
      ],
    );
  }
}

/// Collapsible diagnostics for the failure screen: the technical error
/// detail, the full log, and the cleanup tool — kept off the primary
/// recovery path but one tap away for whoever needs them.
class _TechnicalDetails extends StatelessWidget {
  const _TechnicalDetails({
    required this.detail,
    required this.l10n,
    required this.onViewLog,
    required this.onCleanup,
  });

  final String? detail;
  final AppLocalizations l10n;

  /// Opens the full run log; null when no run was ever launched, which
  /// hides the button entirely (audit F11).
  final VoidCallback? onViewLog;
  final VoidCallback onCleanup;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Theme(
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
        children: [
          if (detail != null) ...[
            CodeBlock(content: detail!),
            const SizedBox(height: AppSpacing.md),
          ],
          if (onViewLog != null) ...[
            SecondaryButton(
              label: l10n.runViewLog,
              icon: Icons.article,
              onPressed: onViewLog,
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          SecondaryButton(
            label: l10n.actionCleanup,
            icon: Icons.cleaning_services,
            onPressed: onCleanup,
          ),
        ],
      ),
    );
  }
}
