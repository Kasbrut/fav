import 'package:fav/core/router/app_router.dart';
import 'package:fav/core/sharing/profile_share_service.dart';
import 'package:fav/core/theme/app_dimens.dart';
import 'package:fav/core/utils/wireguard_tunnel_name.dart';
import 'package:fav/core/widgets/app_card.dart';
import 'package:fav/core/widgets/code_block.dart';
import 'package:fav/core/widgets/detail_row.dart';
import 'package:fav/core/widgets/empty_state.dart';
import 'package:fav/core/widgets/primary_button.dart';
import 'package:fav/core/widgets/qr_container.dart';
import 'package:fav/core/widgets/secondary_button.dart';
import 'package:fav/core/widgets/section_header.dart';
import 'package:fav/features/monitoring/presentation/client_live_status_banner.dart';
import 'package:fav/features/profile/application/client_profile_provider.dart';
import 'package:fav/features/profile/domain/client_profile.dart';
import 'package:fav/features/profile/presentation/widgets/ipv6_profile_status.dart';
import 'package:fav/features/servers/application/server_list_controller.dart';
import 'package:fav/features/servers/domain/wireguard_installation.dart';
import 'package:fav/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Screen presenting the WireGuard client profile produced by an
/// installation (spec §9.1 `ProfileResult`, RF-16): QR code, parsed details,
/// the raw `.conf`, and Copy / Share / Save actions.
class ProfileResultScreen extends ConsumerStatefulWidget {
  /// Creates the [ProfileResultScreen] for the server identified by
  /// [serverId].
  const ProfileResultScreen({required this.serverId, super.key});

  /// Identifier of the server whose saved profile is shown.
  final String serverId;

  @override
  ConsumerState<ProfileResultScreen> createState() =>
      _ProfileResultScreenState();
}

class _ProfileResultScreenState extends ConsumerState<ProfileResultScreen> {
  bool _confExpanded = false;
  bool _profileExported = false;
  bool _clientImportDeclared = false;

  Future<void> _copy(String content) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(profileShareServiceProvider).copyProfile(content);
    } on Object {
      if (mounted) _showExportError();
      return;
    }
    if (!mounted) {
      return;
    }
    messenger.showSnackBar(SnackBar(content: Text(l10n.profileCopied)));
    setState(() => _profileExported = true);
  }

  void _showExportError() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context)!.profileExportFailed),
      ),
    );
  }

  Rect _shareOrigin() {
    final box = context.findRenderObject()! as RenderBox;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  Future<void> _share(String content) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      await ref
          .read(profileShareServiceProvider)
          .shareProfile(
            content: content,
            subject: l10n.profileShareSubject,
            sharePositionOrigin: _shareOrigin(),
          );
      if (mounted) setState(() => _profileExported = true);
    } on Object {
      if (mounted) _showExportError();
    }
  }

  Future<void> _save(String content) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    // The WireGuard apps use the file name as the tunnel name and reject
    // anything over 15 chars or outside their charset, so derive a valid name
    // from the server label rather than the (too long) server UUID.
    final servers = await ref.read(serverListControllerProvider.future);
    final serverLabel =
        servers.where((s) => s.id == widget.serverId).firstOrNull?.label ?? '';
    if (!mounted) {
      return;
    }
    try {
      final saved = await ref
          .read(profileShareServiceProvider)
          .saveProfile(
            suggestedName: wireguardConfFileName(serverLabel: serverLabel),
            content: content,
          );
      if (!mounted || saved == null) {
        return;
      }
      messenger.showSnackBar(SnackBar(content: Text(l10n.profileSaved)));
      setState(() => _profileExported = true);
    } on Object {
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(SnackBar(content: Text(l10n.profileExportFailed)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final async = ref.watch(clientProfileProvider(widget.serverId));
    final server = ref
        .watch(serverListControllerProvider)
        .value
        ?.where((server) => server.id == widget.serverId)
        .firstOrNull;
    return Scaffold(
      appBar: AppBar(
        // Reached either by `.push` from the server detail (back stack
        // available) or by `.go` from the install success screen (no back
        // stack — go_router cleared it on the route switch). Provide a
        // leading button that pops when it can and falls back to the
        // server detail otherwise, so iOS — which has no swipe-back here —
        // always has a visible way out.
        leading: IconButton(
          icon: const BackButtonIcon(),
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go(serverDetailPath(widget.serverId));
            }
          },
        ),
        title: Text(l10n.profileTitle),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        // Route async failures through a localized, generic message — never
        // dump the raw exception (it could end up carrying conf snippets in
        // a future parser change).
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Text(l10n.profileLoadFailed, textAlign: TextAlign.center),
          ),
        ),
        data: (bundle) => bundle == null
            ? EmptyState(
                icon: Icons.vpn_key_off,
                title: l10n.profileNoneSavedTitle,
                message: l10n.profileNoneSavedBody,
              )
            : ClientProfileBodyView(
                serverId: widget.serverId,
                rawConf: bundle.rawConf,
                profile: bundle.profile,
                network: server?.installation?.network,
                profileExported: _profileExported,
                clientImportDeclared: _clientImportDeclared,
                confExpanded: _confExpanded,
                onToggleConf: () =>
                    setState(() => _confExpanded = !_confExpanded),
                onCopy: () => _copy(bundle.rawConf),
                onShare: () => _share(bundle.rawConf),
                onSave: () => _save(bundle.rawConf),
                onShowInstructions: () async {
                  final declared = await context.push<bool>(
                    importInstructionsPath(widget.serverId),
                  );
                  if (mounted && declared == true) {
                    setState(() => _clientImportDeclared = true);
                  }
                },
              ),
      ),
    );
  }
}

/// Reusable body widget for both the legacy `ProfileResultScreen` (serverId-
/// keyed) and the v1.1 `PeerDetailScreen` (peerId-keyed). The peer model
/// passes a `serverId` only to drive `ClientLiveStatusBanner`'s polling.
class ClientProfileBodyView extends StatelessWidget {
  /// Creates a [ClientProfileBodyView].
  const ClientProfileBodyView({
    required this.serverId,
    required this.rawConf,
    required this.profile,
    required this.network,
    required this.profileExported,
    required this.clientImportDeclared,
    required this.confExpanded,
    required this.onToggleConf,
    required this.onCopy,
    required this.onShare,
    required this.onSave,
    required this.onShowInstructions,
    super.key,
  });

  /// Server the displayed profile belongs to (drives M15 live-banner polling).
  final String serverId;

  /// Raw `.conf` text — the QR payload and the body shown when expanded.
  final String rawConf;

  /// Parsed shape used for the detail rows.
  final ClientProfile profile;

  /// Server-side network evidence associated with this profile.
  final NetworkConfiguration? network;

  /// Whether an export action completed in this screen session.
  final bool profileExported;

  /// User declaration returned by the client instructions.
  final bool clientImportDeclared;

  /// Whether the `.conf` body is expanded under the toggle.
  final bool confExpanded;

  /// Called when the expand/collapse toggle is tapped.
  final VoidCallback onToggleConf;

  /// Called by the Copy action.
  final VoidCallback onCopy;

  /// Called by the Share action.
  final VoidCallback onShare;

  /// Called by the Save action.
  final VoidCallback onSave;

  /// Called when the user opens the import-instructions screen.
  final VoidCallback onShowInstructions;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.xxl,
      ),
      children: [
        Ipv6ProfileStatus(
          network: network,
          profileExported: profileExported,
          clientImportDeclared: clientImportDeclared,
        ),
        const SizedBox(height: AppSpacing.lg),
        // M15-T6: live banner driven by the monitoring agent — replaces
        // the static "VPN active" hint. Polls only while this screen is in
        // foreground (Riverpod autoDispose).
        ClientLiveStatusBanner(
          serverId: serverId,
          clientPublicKey: profile.clientPublicKey,
        ),
        const SizedBox(height: AppSpacing.lg),
        Center(child: QrContainer(data: rawConf, size: 260)),
        const SizedBox(height: AppSpacing.md),
        Text(
          l10n.profileScanToImport,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        SectionHeader(label: l10n.profileSectionDetails),
        const SizedBox(height: AppSpacing.sm),
        AppCard(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DetailRow(label: l10n.profileEndpoint, value: profile.endpoint),
              DetailRow(label: l10n.profileAddress, value: profile.address),
              DetailRow(
                label: l10n.profileDns,
                value: profile.dns.isEmpty ? '—' : profile.dns.join(', '),
              ),
              DetailRow(
                label: l10n.profileAllowedIps,
                value: profile.allowedIps.isEmpty
                    ? '—'
                    : profile.allowedIps.join(', '),
              ),
              DetailRow(label: l10n.profileMtu, value: '${profile.mtu}'),
              if (profile.persistentKeepalive != null)
                DetailRow(
                  label: l10n.profileKeepalive,
                  value: l10n.profileKeepaliveSeconds(
                    profile.persistentKeepalive!,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        SectionHeader(label: l10n.profileConfHeading),
        const SizedBox(height: AppSpacing.sm),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: onToggleConf,
            icon: Icon(
              confExpanded ? Icons.expand_less : Icons.expand_more,
              size: 18,
            ),
            label: Text(
              confExpanded ? l10n.profileHideConf : l10n.profileShowConf,
            ),
          ),
        ),
        if (confExpanded) ...[
          const SizedBox(height: AppSpacing.sm),
          // Non-selectable: stops the OS text-selection context menu (long
          // press → "Share with…", "Translate", clipboard managers) from
          // exfiltrating the private key behind the audited Share/Save/Copy
          // buttons. The legitimate flows go through `ProfileShareService`.
          CodeBlock(content: rawConf, selectable: false),
        ],
        const SizedBox(height: AppSpacing.xl),
        PrimaryButton(
          label: l10n.actionShowImportInstructions,
          icon: Icons.help_outline,
          onPressed: onShowInstructions,
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            SecondaryButton(
              label: l10n.actionShare,
              icon: Icons.ios_share,
              onPressed: onShare,
            ),
            SecondaryButton(
              label: l10n.actionCopy,
              icon: Icons.copy,
              onPressed: onCopy,
            ),
            SecondaryButton(
              label: l10n.actionSave,
              icon: Icons.save_alt,
              onPressed: onSave,
            ),
          ],
        ),
      ],
    );
  }
}
