import 'dart:async';

import 'package:fav/core/errors/app_exception.dart';
import 'package:fav/core/errors/error_messages.dart';
import 'package:fav/core/router/app_router.dart';
import 'package:fav/core/theme/app_dimens.dart';
import 'package:fav/core/utils/validators.dart';
import 'package:fav/core/widgets/primary_button.dart';
import 'package:fav/core/widgets/responsive_content.dart';
import 'package:fav/features/help/application/recent_errors_provider.dart';
import 'package:fav/features/help/presentation/error_help_link.dart';
import 'package:fav/features/install/domain/ssh_client.dart';
import 'package:fav/features/peers/application/peers_controller.dart';
import 'package:fav/features/servers/application/server_list_controller.dart';
import 'package:fav/features/servers/presentation/widgets/host_key_dialog.dart';
import 'package:fav/features/servers/presentation/widgets/password_prompt_dialog.dart';
import 'package:fav/features/settings/application/preferences_controller.dart';
import 'package:fav/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Form screen for adding a new peer to [serverId].
class AddPeerScreen extends ConsumerStatefulWidget {
  /// Creates an [AddPeerScreen].
  const AddPeerScreen({required this.serverId, super.key});

  /// Identifier of the server the new peer is being created on.
  final String serverId;

  @override
  ConsumerState<AddPeerScreen> createState() => _AddPeerScreenState();
}

class _AddPeerScreenState extends ConsumerState<AddPeerScreen> {
  final _labelController = TextEditingController();
  bool _submitting = false;
  String? _errorMessage;
  ErrorCode? _lastErrorCode;

  @override
  void dispose() {
    _labelController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context)!;
    final servers = ref.read(serverListControllerProvider).value ?? const [];
    final server = servers.where((s) => s.id == widget.serverId).firstOrNull;
    final label = _labelController.text.trim();
    if (!isValidPeerLabel(label)) {
      setState(() => _errorMessage = l10n.errPeerLabelInvalid);
      return;
    }
    // Always prompt for the account password: even when SSH itself uses
    // key auth (post-hardening), `sudo -S` on the server still requires
    // the user's password to elevate. The resolver below ignores
    // `password` for SSH when a stored key is available.
    final prompted = await showPasswordPrompt(
      context,
      server == null ? widget.serverId : '${server.username}@${server.host}',
    );
    if (prompted == null || prompted.isEmpty || !mounted) {
      return;
    }
    final password = prompted;
    setState(() {
      _submitting = true;
      _errorMessage = null;
      _lastErrorCode = null;
    });
    try {
      final peer = await ref
          .read(peersControllerProvider(widget.serverId).notifier)
          .addPeer(label: label, password: password);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.addPeerSuccessSnack)),
      );
      context.go(peerDetailPath(widget.serverId, peer.id));
    } on HostKeyUnknownException catch (pending) {
      // The host key needs (re-)confirmation — e.g. a legacy MD5-era pin
      // after the SHA-256 migration. Without this, the failure surfaced as
      // a misleading "cannot reach the server" (audit M3, seen live).
      // Confirm, pin, retry.
      if (!mounted) return;
      setState(() => _submitting = false);
      if (await confirmPendingHostKey(context, ref, pending) && mounted) {
        await _submit();
      }
      return;
    } on AppException catch (error) {
      if (!mounted) {
        return;
      }
      ref.read(recentErrorsProvider.notifier).record(error.code);
      unawaited(
        ref
            .read(preferencesControllerProvider.notifier)
            .recordError(error.code.id, DateTime.now()),
      );
      setState(() {
        _errorMessage = localizedErrorMessage(l10n, error.code);
        _lastErrorCode = error.code;
        _submitting = false;
      });
    } on Object {
      if (!mounted) {
        return;
      }
      ref
          .read(recentErrorsProvider.notifier)
          .record(ErrorCode.connHostUnreachable);
      unawaited(
        ref
            .read(preferencesControllerProvider.notifier)
            .recordError(ErrorCode.connHostUnreachable.id, DateTime.now()),
      );
      setState(() {
        _errorMessage = localizedErrorMessage(
          l10n,
          ErrorCode.connHostUnreachable,
        );
        _lastErrorCode = ErrorCode.connHostUnreachable;
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.addPeerScreenTitle)),
      body: ResponsiveContent(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _labelController,
                enabled: !_submitting,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: l10n.addPeerLabelLabel,
                  hintText: l10n.addPeerLabelHint,
                  errorText: _errorMessage,
                ),
                onChanged: (_) {
                  if (_errorMessage != null) {
                    setState(() {
                      _errorMessage = null;
                      _lastErrorCode = null;
                    });
                  }
                },
              ),
              if (_lastErrorCode != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Align(
                  alignment: Alignment.centerLeft,
                  child: ErrorHelpButton(code: _lastErrorCode!),
                ),
              ],
              const SizedBox(height: AppSpacing.xl),
              PrimaryButton(
                label: l10n.actionAddPeer,
                icon: Icons.person_add_alt_1,
                isLoading: _submitting,
                onPressed: _submitting ? null : _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
