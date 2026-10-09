import 'dart:async';

import 'package:fav/core/errors/app_exception.dart';
import 'package:fav/core/errors/error_messages.dart';
import 'package:fav/core/router/app_router.dart';
import 'package:fav/core/theme/app_dimens.dart';
import 'package:fav/core/widgets/app_banner.dart';
import 'package:fav/core/widgets/app_card.dart';
import 'package:fav/core/widgets/detail_row.dart';
import 'package:fav/core/widgets/monospace_text.dart';
import 'package:fav/core/widgets/primary_button.dart';
import 'package:fav/core/widgets/responsive_content.dart';
import 'package:fav/core/widgets/secondary_button.dart';
import 'package:fav/core/widgets/section_header.dart';
import 'package:fav/core/widgets/status_badge.dart';
import 'package:fav/features/help/application/recent_errors_provider.dart';
import 'package:fav/features/help/presentation/error_help_link.dart';
import 'package:fav/features/install/application/user_key_service.dart';
import 'package:fav/features/install/data/ssh/host_key_change_registry.dart';
import 'package:fav/features/install/domain/ssh_client.dart';
import 'package:fav/features/monitoring/application/monitor_polling_controller.dart';
import 'package:fav/features/monitoring/domain/client_live_status.dart';
import 'package:fav/features/peers/application/peers_controller.dart';
import 'package:fav/features/peers/presentation/peers_list_section.dart';
import 'package:fav/features/servers/application/server_list_controller.dart';
import 'package:fav/features/servers/domain/host_key_fingerprint.dart';
import 'package:fav/features/servers/domain/server.dart';
import 'package:fav/features/servers/domain/server_metadata.dart';
import 'package:fav/features/servers/domain/wireguard_installation.dart';
import 'package:fav/features/servers/presentation/widgets/host_key_dialog.dart';
import 'package:fav/features/servers/presentation/widgets/password_prompt_dialog.dart';
import 'package:fav/features/servers/presentation/widgets/server_state_indicator.dart';
import 'package:fav/features/servers/presentation/widgets/server_teardown_modal.dart';
import 'package:fav/features/servers/presentation/widgets/ssh_key_editor.dart';
import 'package:fav/features/settings/application/preferences_controller.dart';
import 'package:fav/features/shell/application/pending_shell_password.dart';
import 'package:fav/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

/// Detail screen for a single server: metadata, re-probe, removal (§9.1).
class ServerDetailScreen extends ConsumerStatefulWidget {
  /// Creates the detail screen for the server identified by [serverId].
  const ServerDetailScreen({required this.serverId, super.key});

  /// Identifier of the server to display.
  final String serverId;

  @override
  ConsumerState<ServerDetailScreen> createState() => _ServerDetailScreenState();
}

class _ServerDetailScreenState extends ConsumerState<ServerDetailScreen> {
  bool _busy = false;
  bool _portCheckBusy = false;
  String? _autoCheckedServerId;

  Future<void> _checkWireguardPort(
    Server server, {
    required bool allowPasswordPrompt,
  }) async {
    if (_portCheckBusy || server.installation == null) return;
    final l10n = AppLocalizations.of(context)!;
    setState(() => _portCheckBusy = true);
    try {
      var result = await ref
          .read(serverListControllerProvider.notifier)
          .checkWireguardPort(server);
      if (result == WireguardPortReachability.unknown &&
          allowPasswordPrompt &&
          server.username != 'root' &&
          mounted) {
        final password = await showPasswordPrompt(
          context,
          '${server.username}@${server.host}',
        );
        if (password != null && password.isNotEmpty) {
          result = await ref
              .read(serverListControllerProvider.notifier)
              .checkWireguardPort(server, password: password);
        }
      }
      if (allowPasswordPrompt &&
          result == WireguardPortReachability.unknown &&
          mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.wireguardPortCheckUnavailable)),
        );
      }
    } on Object {
      if (allowPasswordPrompt && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.wireguardPortCheckUnavailable)),
        );
      }
    } finally {
      if (mounted) setState(() => _portCheckBusy = false);
    }
  }

  Future<void> _reprobe(Server server) async {
    final l10n = AppLocalizations.of(context)!;
    String? password;
    if (server.requiresPasswordForSsh) {
      password = await showPasswordPrompt(
        context,
        '${server.username}@${server.host}',
      );
      if (password == null || password.isEmpty || !mounted) {
        return;
      }
    }
    setState(() => _busy = true);
    try {
      await ref
          .read(serverListControllerProvider.notifier)
          .reprobe(server, password: password);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.reprobeSuccess)),
        );
      }
    } on HostKeyUnknownException catch (pending) {
      // The host key needs (re-)confirmation — a legacy MD5-era pin after
      // the SHA-256 migration, or a first contact. Confirm, pin, retry;
      // the upgraded pin then serves every other flow too (audit M3).
      if (!mounted) return;
      setState(() => _busy = false);
      if (await confirmPendingHostKey(context, ref, pending) && mounted) {
        await _reprobe(server);
      }
      return;
    } on AppException catch (error) {
      if (mounted) {
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
    } on Object {
      if (mounted) {
        ref
            .read(recentErrorsProvider.notifier)
            .record(ErrorCode.connHostUnreachable);
        unawaited(
          ref
              .read(preferencesControllerProvider.notifier)
              .recordError(ErrorCode.connHostUnreachable.id, DateTime.now()),
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              localizedErrorMessage(l10n, ErrorCode.connHostUnreachable),
            ),
            action: errorHelpSnackBarAction(
              context,
              ref,
              ErrorCode.connHostUnreachable,
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _openShell(Server server) async {
    String? password;
    if (server.requiresPasswordForSsh) {
      password = await showPasswordPrompt(
        context,
        '${server.username}@${server.host}',
      );
      if (password == null || password.isEmpty || !mounted) {
        return;
      }
    }
    if (mounted) {
      if (password != null) {
        ref.read(pendingShellPasswordsProvider).put(server.id, password);
      }
      await context.push(sshShellPath(server.id));
      // Belt-and-braces: the shell screen takes the entry on first frame,
      // but if the route never consumed it (a throwing builder, a future
      // redirect) the cleartext must not outlive the operation.
      ref.read(pendingShellPasswordsProvider).take(server.id);
    }
  }

  Future<void> _replaceFingerprint(
    Server server,
    HostKeyFingerprint replacement,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showHostKeyReplacementDialog(
      context,
      current: server.pinnedHostKey!,
      replacement: replacement,
    );
    if (confirmed != true || !mounted) return;
    String? password;
    if (server.requiresPasswordForSsh) {
      password = await showPasswordPrompt(
        context,
        '${server.username}@${server.host}',
      );
      if (password == null || password.isEmpty || !mounted) return;
    }
    setState(() => _busy = true);
    try {
      await ref
          .read(serverListControllerProvider.notifier)
          .replaceHostKey(server, replacement, password: password);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.hostKeyReplaceSuccess)),
        );
      }
    } on AppException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(localizedErrorMessage(l10n, error.code))),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(Server server) async {
    await showTeardownModal(context, server);
    // If the server was removed by the modal, the list provider refreshes and
    // the server disappears from the watch below; the detail screen shows
    // "Server not found" which offers a back button. Navigate back proactively
    // when the server is no longer in the list.
    if (!mounted) return;
    final servers = ref.read(serverListControllerProvider).value ?? const [];
    final stillExists = servers.any((s) => s.id == server.id);
    if (!stillExists) {
      context.go(serverListRoute);
    }
  }

  /// Opens the add-key dialog and deploys the chosen key to [server] over a
  /// live SSH session (the "later, at any time" path).
  Future<void> _addKey(Server server) async {
    final l10n = AppLocalizations.of(context)!;
    final line = await showAddSshKeyDialog(context);
    if (line == null || !mounted) {
      return;
    }
    if (server.userAuthorizedKeys.contains(line)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.sshKeyDuplicate)),
      );
      return;
    }
    await _runKeyOp(
      server,
      (password) => ref
          .read(userKeyServiceProvider)
          .addKeys(
            server: server,
            keyLines: [line],
            password: password,
          ),
      successMessage: l10n.sshKeyAddedSnack,
    );
  }

  /// Confirms, then removes [line] from [server]'s management account.
  Future<void> _removeKey(Server server, String line) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.sshKeyRemoveTitle),
        content: Text(l10n.sshKeyRemoveMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.actionRemove),
          ),
        ],
      ),
    );
    if (!(confirmed ?? false) || !mounted) {
      return;
    }
    await _runKeyOp(
      server,
      (password) => ref
          .read(userKeyServiceProvider)
          .removeKey(
            server: server,
            keyLine: line,
            password: password,
          ),
      successMessage: l10n.sshKeyRemovedSnack,
    );
  }

  /// Shared driver for the SSH key add/remove operations: prompts for the
  /// password when the server has no stored key, runs [op], refreshes the list
  /// and reports success or a mapped error. Mirrors [_reprobe].
  Future<void> _runKeyOp(
    Server server,
    Future<void> Function(String? password) op, {
    required String successMessage,
  }) async {
    String? password;
    if (server.requiresPasswordForSsh) {
      password = await showPasswordPrompt(
        context,
        '${server.username}@${server.host}',
      );
      if (password == null || password.isEmpty || !mounted) {
        return;
      }
    }
    setState(() => _busy = true);
    try {
      await op(password);
      if (!mounted) {
        return;
      }
      await ref.read(serverListControllerProvider.notifier).refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(successMessage)),
        );
      }
    } on HostKeyUnknownException catch (pending) {
      // Confirm-pin-retry, like every interactive SSH entry point (M3).
      if (!mounted) return;
      setState(() => _busy = false);
      if (await confirmPendingHostKey(context, ref, pending) && mounted) {
        await _runKeyOp(server, op, successMessage: successMessage);
      }
      return;
    } on AppException catch (error) {
      if (mounted) {
        _reportError(error.code);
      }
    } on Object {
      if (mounted) {
        _reportError(ErrorCode.connHostUnreachable);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  /// Records [code] for the help surfaces and shows it as a snackbar with a
  /// troubleshooting action.
  void _reportError(ErrorCode code) {
    final l10n = AppLocalizations.of(context)!;
    ref.read(recentErrorsProvider.notifier).record(code);
    unawaited(
      ref
          .read(preferencesControllerProvider.notifier)
          .recordError(code.id, DateTime.now()),
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(localizedErrorMessage(l10n, code)),
        action: errorHelpSnackBarAction(context, ref, code),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final serversAsync = ref.watch(serverListControllerProvider);
    final servers = serversAsync.value ?? const <Server>[];
    final matches = servers.where((s) => s.id == widget.serverId);
    final server = matches.isEmpty ? null : matches.first;

    // Reached via `.push` from the server list (back stack present) or via
    // `.go` from the profile screen's back button (no back stack — go_router
    // cleared it). Provide a leading button that pops when it can and falls
    // back to the home (server list) otherwise, so iOS — which has no
    // swipe-back here — always has a visible way out.
    final leading = IconButton(
      icon: const BackButtonIcon(),
      tooltip: MaterialLocalizations.of(context).backButtonTooltip,
      onPressed: () {
        if (context.canPop()) {
          context.pop();
        } else {
          context.go(serverListRoute);
        }
      },
    );

    if (server == null) {
      // Distinguish "still loading the list" from "this id is genuinely
      // gone": otherwise the screen flashes "Server not found" on first frame.
      return Scaffold(
        appBar: AppBar(leading: leading),
        body: Center(
          child: serversAsync.isLoading
              ? const CircularProgressIndicator()
              : Text(l10n.detailServerNotFound),
        ),
      );
    }

    final fingerprint = server.pinnedHostKey;
    final detectedHostKey = ref.watch(
      hostKeyChangeRegistryProvider,
    )[HostKeyChangeRegistry.keyFor(server.host, server.sshPort)];
    final canViewHistory = server.installation != null;
    if (server.installation != null && _autoCheckedServerId != server.id) {
      _autoCheckedServerId = server.id;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(
            _checkWireguardPort(server, allowPasswordPrompt: false),
          );
        }
      });
    }
    return Scaffold(
      appBar: AppBar(
        leading: leading,
        title: Text(l10n.detailTitle),
        actions: [
          IconButton(
            onPressed: () => _openShell(server),
            icon: const Icon(Icons.terminal),
            tooltip: l10n.shellOpenTooltip,
          ),
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: IconButton(
              onPressed: canViewHistory
                  ? () => context.push(serverHistoryPath(server.id))
                  : null,
              icon: const Icon(Icons.timeline),
              tooltip: l10n.historyOpenTooltip,
            ),
          ),
        ],
      ),
      body: ResponsiveContent(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.xxl,
          ),
          children: [
            _DetailHeader(server: server),
            if (server.installation?.portReachability ==
                WireguardPortReachability.blocked) ...[
              const SizedBox(height: AppSpacing.lg),
              _WireguardPortBanner(
                server: server,
                busy: _portCheckBusy,
                onCheckAgain: () => _checkWireguardPort(
                  server,
                  allowPasswordPrompt: true,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            _SystemSection(metadata: server.metadata),
            const SizedBox(height: AppSpacing.lg),
            _WireguardSection(
              installation: server.installation,
              serverId: server.id,
              portCheckBusy: _portCheckBusy,
              onCheckPort: () => _checkWireguardPort(
                server,
                allowPasswordPrompt: true,
              ),
            ),
            if (server.installation != null) ...[
              const SizedBox(height: AppSpacing.lg),
              PeersListSection(serverId: server.id),
            ],
            if (fingerprint != null) ...[
              const SizedBox(height: AppSpacing.lg),
              _FingerprintSection(
                fingerprint: fingerprint,
                busy: _busy,
                detectedReplacement: detectedHostKey,
                onReplace: detectedHostKey == null
                    ? null
                    : () => _replaceFingerprint(server, detectedHostKey),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            SectionHeader(
              label: l10n.sshKeysSectionTitle,
              hint: l10n.sshKeysSectionHint,
            ),
            const SizedBox(height: AppSpacing.sm),
            SshKeyListCard(
              keys: server.userAuthorizedKeys,
              busy: _busy,
              onAdd: () => _addKey(server),
              onRemove: (line) => _removeKey(server, line),
            ),
            const SizedBox(height: AppSpacing.xl),
            PrimaryButton(
              label: l10n.actionReprobe,
              icon: Icons.refresh,
              isLoading: _busy,
              onPressed: () => _reprobe(server),
            ),
            const SizedBox(height: AppSpacing.sm),
            SecondaryButton(
              label: l10n.actionRemoveServer,
              icon: Icons.delete_outline,
              onPressed: _busy ? null : () => _remove(server),
            ),
          ],
        ),
      ),
    );
  }
}

class _WireguardPortBanner extends StatelessWidget {
  const _WireguardPortBanner({
    required this.server,
    required this.busy,
    required this.onCheckAgain,
  });

  final Server server;
  final bool busy;
  final VoidCallback onCheckAgain;

  @override
  Widget build(BuildContext context) {
    final installation = server.installation!;
    final l10n = AppLocalizations.of(context)!;
    return AppBanner(
      variant: AppBannerVariant.warning,
      icon: Icons.gpp_maybe_outlined,
      title: l10n.wireguardPortBlockedTitle,
      message: l10n.wireguardPortBlockedMessage(installation.listenPort),
      action: Wrap(
        spacing: AppSpacing.sm,
        alignment: WrapAlignment.end,
        children: [
          TextButton.icon(
            onPressed: busy ? null : onCheckAgain,
            icon: busy
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            label: Text(l10n.actionCheckPortAgain),
          ),
          TextButton.icon(
            onPressed: () => context.push('/help/firewall'),
            icon: const Icon(Icons.menu_book_outlined),
            label: Text(l10n.actionOpenFirewallGuide),
          ),
        ],
      ),
    );
  }
}

/// The server name, connection string and status badges shown at the top.
///
/// The installed badge is dynamic when a monitoring snapshot is available:
/// it shows the number of currently-online clients instead of the static
/// "WireGuard active" label, so the badge actually carries information.
/// Falls back to "WireGuard installed" when the agent is not present.
class _DetailHeader extends ConsumerWidget {
  const _DetailHeader({required this.server});

  final Server server;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final hardened = server.installation?.hardeningApplied ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(server.label, style: theme.textTheme.headlineSmall),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            ServerStateIndicator(server: server),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              // Selectable so the user can copy the SSH connection string,
              // like the fingerprint below.
              child: MonospaceText(
                '${server.username}@${server.host}:${server.sshPort}',
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            _InstallStatusBadge(server: server),
            if (hardened)
              StatusBadge(
                label: l10n.statusHardened,
                variant: StatusBadgeVariant.info,
                icon: Icons.shield_outlined,
              ),
          ],
        ),
      ],
    );
  }
}

/// The first badge in the detail header.
///
/// When the server is not yet installed it is a static "Not installed"
/// pill. Once installed it consumes the monitoring polling state and shows
/// the live count of connected clients ("2 clients connected") instead of
/// the previous, always-the-same "WireGuard active" label. If the
/// monitoring agent is missing (or polling has not produced a snapshot
/// yet) it falls back to the factual "WireGuard installed".
class _InstallStatusBadge extends ConsumerWidget {
  const _InstallStatusBadge({required this.server});

  final Server server;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    if (server.installation == null) {
      return StatusBadge(label: l10n.statusNotInstalled);
    }
    final polling = ref.watch(monitorPollingControllerProvider(server.id));
    final agentMissing =
        polling.lastErrorReason == ClientLiveStatusUnknownReason.notInstalled;
    if (polling.snapshot == null || agentMissing) {
      return StatusBadge(
        label: l10n.statusWireguardInstalled,
        variant: StatusBadgeVariant.success,
        icon: Icons.check,
      );
    }
    final onlineCount = polling.snapshot!.peers
        .where((peer) => peer.online)
        .length;
    return StatusBadge(
      label: l10n.statusPeersConnected(onlineCount),
      variant: onlineCount > 0
          ? StatusBadgeVariant.success
          : StatusBadgeVariant.neutral,
      icon: onlineCount > 0 ? Icons.cloud_done : Icons.cloud_off,
    );
  }
}

class _SystemSection extends StatelessWidget {
  const _SystemSection({required this.metadata});

  final ServerMetadata? metadata;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final data = metadata;
    return _Section(
      title: l10n.detailSectionSystem,
      children: data == null
          ? [Text(l10n.detailNotProbed)]
          : [
              DetailRow(label: l10n.metaOs, value: data.prettyName),
              DetailRow(label: l10n.metaKernel, value: data.kernelVersion),
              DetailRow(
                label: l10n.metaArchitecture,
                value: data.architecture,
              ),
              DetailRow(label: l10n.metaHostname, value: data.hostname),
              DetailRow(
                label: l10n.metaMemory,
                value: '${data.totalMemoryMb} MB',
              ),
              DetailRow(label: l10n.metaCpu, value: '${data.cpuCount}'),
              DetailRow(label: l10n.metaPublicIp, value: data.publicIp),
              DetailRow(
                label: l10n.metaInterfaces,
                value: data.networkInterfaces.join(', '),
              ),
            ],
    );
  }
}

/// The WireGuard section: interface, subnet and peers once installed —
/// or the install entry point while nothing is installed yet.
class _WireguardSection extends ConsumerWidget {
  const _WireguardSection({
    required this.installation,
    required this.serverId,
    required this.portCheckBusy,
    required this.onCheckPort,
  });

  final WireguardInstallation? installation;
  final String serverId;
  final bool portCheckBusy;
  final VoidCallback onCheckPort;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final wg = installation;
    // Count the peers actually stored for this server: the installation
    // record's list is written once (empty) at finalize and never
    // maintained afterwards (device test 2026-08-19).
    final peerCount = ref
        .watch(peersControllerProvider(serverId))
        .value
        ?.length;
    return _Section(
      title: l10n.detailSectionWireguard,
      children: wg == null
          ? [
              Text(l10n.detailNotInstalled),
              const SizedBox(height: AppSpacing.md),
              PrimaryButton(
                label: l10n.actionInstallWireguard,
                icon: Icons.download,
                onPressed: () => context.push(installServerPath(serverId)),
              ),
            ]
          : [
              DetailRow(
                label: l10n.detailWgInterface,
                value: '${wg.interfaceName} · UDP ${wg.listenPort}',
              ),
              DetailRow(label: l10n.detailWgSubnet, value: wg.vpnSubnet),
              if (wg.network?.ipv6Mode case final ipv6Mode?)
                DetailRow(
                  label: 'IPv6',
                  value: ipv6Mode == Ipv6Mode.routed
                      ? l10n.ipv6StatusRoutedTitle
                      : ipv6Mode == Ipv6Mode.blocked
                      ? l10n.ipv6StatusBlockedTitle
                      : l10n.ipv6StatusUnavailableTitle,
                ),
              DetailRow(
                label: l10n.detailWgPeers,
                value: '${peerCount ?? wg.peers.length}',
              ),
              DetailRow(
                label: l10n.detailWgPortStatus,
                value: _portStatusLabel(l10n, wg),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: portCheckBusy ? null : onCheckPort,
                  icon: portCheckBusy
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                  label: Text(l10n.actionCheckPortAgain),
                ),
              ),
            ],
    );
  }

  String _portStatusLabel(
    AppLocalizations l10n,
    WireguardInstallation installation,
  ) {
    final status = switch (installation.portReachability) {
      WireguardPortReachability.reachable => l10n.wireguardPortReachable,
      WireguardPortReachability.blocked => l10n.wireguardPortBlocked,
      WireguardPortReachability.unknown => l10n.wireguardPortNotChecked,
    };
    final checkedAt = installation.portCheckedAt;
    if (checkedAt == null) return status;
    final formatted = DateFormat.yMMMd(
      l10n.localeName,
    ).add_Hm().format(checkedAt.toLocal());
    return l10n.wireguardPortStatusChecked(status, formatted);
  }
}

/// The pinned SSH host-key fingerprint section (spec §10, Trust On First Use).
class _FingerprintSection extends StatelessWidget {
  const _FingerprintSection({
    required this.fingerprint,
    required this.busy,
    required this.detectedReplacement,
    required this.onReplace,
  });

  final HostKeyFingerprint fingerprint;
  final bool busy;
  final HostKeyFingerprint? detectedReplacement;
  final VoidCallback? onReplace;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(label: l10n.detailSectionFingerprint),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          width: double.infinity,
          child: Card(
            color: detectedReplacement == null
                ? null
                : theme.colorScheme.errorContainer,
            shape: detectedReplacement == null
                ? null
                : RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadii.card),
                    side: BorderSide(color: theme.colorScheme.error),
                  ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (detectedReplacement != null) ...[
                        Row(
                          children: [
                            Icon(
                              Icons.warning_amber_rounded,
                              color: theme.colorScheme.error,
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Text(
                                l10n.hostKeyChangedTitle,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  color: theme.colorScheme.error,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.md),
                      ],
                      MonospaceText(
                        '${fingerprint.hashAlgorithm.toUpperCase()}:'
                        '${fingerprint.fingerprint}',
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        l10n.detailFingerprintMeta(
                          fingerprint.keyType,
                          DateFormat.yMMMd().format(fingerprint.pinnedAt),
                        ),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (detectedReplacement != null) ...[
                        const SizedBox(height: AppSpacing.sm),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: busy ? null : onReplace,
                            icon: const Icon(Icons.sync_lock_outlined),
                            label: Text(l10n.hostKeyReplaceAction),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(label: title),
        const SizedBox(height: AppSpacing.sm),
        AppCard(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        ),
      ],
    );
  }
}
