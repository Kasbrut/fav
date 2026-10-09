import 'dart:async';

import 'package:fav/core/errors/error_messages.dart';
import 'package:fav/core/router/app_router.dart';
import 'package:fav/core/theme/app_dimens.dart';
import 'package:fav/core/widgets/app_banner.dart';
import 'package:fav/core/widgets/app_card.dart';
import 'package:fav/core/widgets/app_search_field.dart';
import 'package:fav/core/widgets/code_block.dart';
import 'package:fav/core/widgets/empty_state.dart';
import 'package:fav/core/widgets/responsive_app_bar.dart';
import 'package:fav/features/help/application/recent_errors_provider.dart';
import 'package:fav/features/help/presentation/error_help_link.dart';
import 'package:fav/features/install/application/install_controller.dart';
import 'package:fav/features/install/application/run_recovery_provider.dart';
import 'package:fav/features/install/application/run_recovery_service.dart';
import 'package:fav/features/install/domain/install_run.dart';
import 'package:fav/features/servers/application/server_list_controller.dart';
import 'package:fav/features/servers/domain/server.dart';
import 'package:fav/features/servers/presentation/widgets/password_prompt_dialog.dart';
import 'package:fav/features/servers/presentation/widgets/server_card.dart';
import 'package:fav/features/servers/presentation/widgets/server_teardown_modal.dart';
import 'package:fav/features/settings/application/preferences_controller.dart';
import 'package:fav/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Home screen showing the list of registered servers (spec §9.1).
class ServerListScreen extends ConsumerStatefulWidget {
  /// Creates the server list screen.
  const ServerListScreen({super.key});

  @override
  ConsumerState<ServerListScreen> createState() => _ServerListScreenState();
}

class _ServerListScreenState extends ConsumerState<ServerListScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final serversAsync = ref.watch(serverListControllerProvider);
    // A thumb-reachable, labelled add action for the populated list. The
    // empty state carries its own focal CTA, so the FAB would be redundant
    // there; show it only once there are servers.
    final hasServers = serversAsync.value?.isNotEmpty ?? false;
    return Scaffold(
      appBar: ResponsiveAppBar(
        title: l10n.serverListTitle,
        maxContentWidth: AppSizes.contentMaxWidth,
      ),
      floatingActionButton: hasServers
          ? FloatingActionButton.extended(
              onPressed: () => context.push(addServerRoute),
              icon: const Icon(Icons.add),
              label: Text(l10n.actionAddServer),
            )
          : null,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: AppSizes.contentMaxWidth,
          ),
          child: Column(
            children: [
              const _IncompleteRunsBanner(),
              Expanded(
                child: serversAsync.when(
                  loading: () => const _ServerListSkeleton(),
                  error: (error, _) => _ServerListError(error),
                  data: (servers) => _buildData(l10n, servers),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildData(AppLocalizations l10n, List<Server> servers) {
    if (servers.isEmpty) {
      return EmptyState(
        icon: Icons.dns_outlined,
        title: l10n.serverListEmptyTitle,
        message: l10n.serverListEmptyBody,
        // First-run focal action: the home screen's whole job at zero-state
        // is to invite the first server, so the CTA lives here, not only in
        // the app bar.
        action: FilledButton.icon(
          onPressed: () => context.push(addServerRoute),
          icon: const Icon(Icons.add),
          label: Text(l10n.actionAddServer),
        ),
      );
    }
    final filtered = _query.isEmpty
        ? servers
        : servers.where(_matchesQuery).toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: AppSearchField(
            hintText: l10n.serverSearchHint,
            controller: _searchController,
            onChanged: (value) =>
                setState(() => _query = value.trim().toLowerCase()),
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? EmptyState(title: l10n.serverSearchEmpty)
              : _ServerList(filtered),
        ),
      ],
    );
  }

  bool _matchesQuery(Server server) {
    final connection = '${server.username}@${server.host}';
    return server.label.toLowerCase().contains(_query) ||
        connection.toLowerCase().contains(_query);
  }
}

/// Banner offering to resume an interrupted installation run (spec §6.4).
class _IncompleteRunsBanner extends ConsumerWidget {
  const _IncompleteRunsBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    // While an install flow is in flight the controller refuses any attach
    // (audit M2) — offering a Resume that would silently no-op is worse than
    // hiding the banner until the flow reaches a terminal state.
    final flowBusy = switch (ref.watch(installControllerProvider)) {
      InstallIdle() || InstallFailure() || InstallSuccess() => false,
      _ => true,
    };
    if (flowBusy) {
      return const SizedBox.shrink();
    }
    final runs = ref.watch(incompleteRunsProvider).value ?? const [];
    final servers = ref.watch(serverListControllerProvider).value ?? const [];
    // Pair each interrupted run with its server, dropping any whose server was
    // removed. The banner resumes the first resumable run and counts the rest,
    // so a deleted-server run never hides the others (or the whole banner).
    final resumable = <(InstallRun, Server)>[];
    for (final run in runs) {
      final match = servers.where((server) => server.id == run.serverId);
      if (match.isNotEmpty) resumable.add((run, match.first));
    }
    if (resumable.isEmpty) {
      return const SizedBox.shrink();
    }
    final (run, server) = resumable.first;
    final extra = resumable.length - 1;
    final message = extra > 0
        ? '${l10n.incompleteRunBody(server.label)} '
              '${l10n.incompleteRunMore(extra)}'
        : l10n.incompleteRunBody(server.label);
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: AppBanner(
        variant: AppBannerVariant.warning,
        icon: Icons.history,
        title: l10n.incompleteRunTitle,
        message: message,
        action: FilledButton(
          onPressed: () => _resume(context, ref, run, server, l10n),
          child: Text(l10n.actionResume),
        ),
      ),
    );
  }

  Future<void> _resume(
    BuildContext context,
    WidgetRef ref,
    InstallRun run,
    Server server,
    AppLocalizations l10n,
  ) async {
    String? password;
    if (server.requiresPasswordForSsh) {
      password = await showPasswordPrompt(
        context,
        '${server.username}@${server.host}',
      );
      if (password == null || !context.mounted) {
        return;
      }
    }
    final outcome = await ref
        .read(runRecoveryServiceProvider)
        .recover(localRun: run, password: password);
    if (!context.mounted) {
      // The recovered connection would otherwise have no owner: close it so a
      // still-open RecoveryResumePolling client is not leaked (audit M7).
      if (outcome is RecoveryResumePolling) {
        unawaited(outcome.client.close());
      }
      return;
    }
    ref.invalidate(incompleteRunsProvider);
    switch (outcome) {
      case RecoveryResumePolling(:final client, :final paths):
        unawaited(
          ref
              .read(installControllerProvider.notifier)
              .attachRecovered(
                client: client,
                run: run,
                paths: paths,
                server: server,
                sshPassword: password,
              ),
        );
        context.go(installProgressRoute);
      case RecoveryCompleted():
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.recoveryCompletedMessage)),
        );
      case RecoveryOrphaned():
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(l10n.recoveryOrphanedTitle),
            content: Text(l10n.recoveryOrphanedMessage),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l10n.actionCancel),
              ),
            ],
          ),
        );
      case RecoveryFailed(:final error):
        ref.read(recentErrorsProvider.notifier).record(error.code);
        unawaited(
          ref
              .read(preferencesControllerProvider.notifier)
              .recordError(error.code.id, DateTime.now()),
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(localizedErrorMessage(l10n, error.code)),
            action: errorHelpSnackBarAction(context, ref, error.code),
          ),
        );
    }
  }
}

/// The list-load failure view: a plain message and a Retry, with the raw
/// error kept behind a technical-details disclosure (spec §11.1 contract).
class _ServerListError extends ConsumerWidget {
  const _ServerListError(this.error);

  final Object error;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    return EmptyState(
      icon: Icons.cloud_off_outlined,
      title: l10n.serverListErrorTitle,
      message: l10n.serverListErrorBody,
      action: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FilledButton.icon(
              onPressed: () => ref.invalidate(serverListControllerProvider),
              icon: const Icon(Icons.refresh),
              label: Text(l10n.actionRetry),
            ),
            const SizedBox(height: AppSpacing.md),
            _ErrorDetails(detail: '$error'),
          ],
        ),
      ),
    );
  }
}

/// A flat, collapsible disclosure holding the raw error text, off the primary
/// recovery path but one tap away for whoever needs it.
class _ErrorDetails extends StatelessWidget {
  const _ErrorDetails({required this.detail});

  final String detail;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
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
        children: [CodeBlock(content: detail)],
      ),
    );
  }
}

/// A calm, static loading placeholder that mirrors the server cards, shown
/// instead of a centred spinner while the list reads from local storage.
class _ServerListSkeleton extends StatelessWidget {
  const _ServerListSkeleton();

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: List.generate(
          3,
          (_) => const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: _SkeletonCard(),
          ),
        ),
      ),
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard();

  @override
  Widget build(BuildContext context) {
    return const AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _SkeletonBox(width: 10, height: 10, radius: 5),
              SizedBox(width: AppSpacing.sm),
              _SkeletonBox(width: 140, height: 14),
            ],
          ),
          SizedBox(height: AppSpacing.sm),
          _SkeletonBox(width: 200, height: 12),
          SizedBox(height: AppSpacing.md),
          Row(
            children: [
              _SkeletonBox(width: 64, height: 20),
              SizedBox(width: AppSpacing.sm),
              _SkeletonBox(width: 92, height: 20),
            ],
          ),
        ],
      ),
    );
  }
}

class _SkeletonBox extends StatelessWidget {
  const _SkeletonBox({
    required this.width,
    required this.height,
    this.radius = AppRadii.badge,
  });

  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

class _ServerList extends ConsumerWidget {
  const _ServerList(this.servers);

  final List<Server> servers;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(serverListControllerProvider.notifier);
    return RefreshIndicator(
      onRefresh: controller.refresh,
      child: ListView.builder(
        // Extra bottom padding so the extended FAB never covers the last card.
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, 80),
        itemCount: servers.length,
        itemBuilder: (context, index) {
          final server = servers[index];
          return Dismissible(
            key: ValueKey(server.id),
            direction: DismissDirection.endToStart,
            background: const _DeleteBackground(),
            confirmDismiss: (_) async {
              await showTeardownModal(context, server);
              // The modal/controller perform the removal and list refresh;
              // always return false so Dismissible never auto-removes.
              return false;
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: ServerCard(
                server: server,
                onTap: () => context.push(serverDetailPath(server.id)),
                onRemove: () => showTeardownModal(context, server),
                onInstall: server.installation == null
                    ? () => context.push(installServerPath(server.id))
                    : null,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _DeleteBackground extends StatelessWidget {
  const _DeleteBackground();

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      margin: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(AppRadii.card),
      ),
      child: Icon(
        Icons.delete_outline,
        color: Theme.of(context).colorScheme.onErrorContainer,
      ),
    );
  }
}
