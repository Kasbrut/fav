import 'dart:async';

import 'package:fav/core/router/app_router.dart';
import 'package:fav/core/theme/app_dimens.dart';
import 'package:fav/core/utils/password_strength.dart';
import 'package:fav/core/utils/validators.dart';
import 'package:fav/core/widgets/app_banner.dart';
import 'package:fav/core/widgets/app_text_field.dart';
import 'package:fav/core/widgets/password_strength_bar.dart';
import 'package:fav/core/widgets/primary_button.dart';
import 'package:fav/core/widgets/responsive_content.dart';
import 'package:fav/core/widgets/secondary_button.dart';
import 'package:fav/features/install/application/install_controller.dart';
import 'package:fav/features/install/application/install_form_controller.dart';
import 'package:fav/features/install/domain/new_user_spec.dart';
import 'package:fav/features/servers/application/server_list_controller.dart';
import 'package:fav/features/servers/domain/server.dart';
import 'package:fav/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Starts the WireGuard installation on an already-registered server.
///
/// The add-server flow remains the first-run entry point; this screen covers
/// the two cases that used to be dead ends: a server whose install failed,
/// and a server registered without installing. Same credentials contract as
/// the add flow: the login password is held in memory for the run only, and
/// a root login requires a management user to be created (spec §10.2).
class InstallServerScreen extends ConsumerStatefulWidget {
  /// Creates an [InstallServerScreen] for [serverId].
  const InstallServerScreen({required this.serverId, super.key});

  /// Identifier of the registered server to install onto.
  final String serverId;

  @override
  ConsumerState<InstallServerScreen> createState() =>
      _InstallServerScreenState();
}

class _InstallServerScreenState extends ConsumerState<InstallServerScreen> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _newUsername = TextEditingController();
  final _newPassword = TextEditingController();
  final _confirmPassword = TextEditingController();
  bool _isLaunching = false;

  @override
  void initState() {
    super.initState();
    _newPassword.addListener(_onNewPasswordChanged);
  }

  /// Re-renders the strength bar as the new password is typed.
  void _onNewPasswordChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _newPassword.removeListener(_onNewPasswordChanged);
    // Best-effort: drop the password text before releasing the controllers.
    for (final controller in [_password, _newPassword, _confirmPassword]) {
      controller.clear();
    }
    _password.dispose();
    _newUsername.dispose();
    _newPassword.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  Future<void> _startInstall(Server server) async {
    if (_isLaunching) return;
    final l10n = AppLocalizations.of(context)!;
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    final isRootLogin = server.username == 'root';
    if (isRootLogin &&
        evaluatePasswordStrength(_newPassword.text) == PasswordStrength.weak) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.errPasswordTooWeak)),
      );
      return;
    }
    final newUser = isRootLogin
        ? NewUserSpec(
            username: _newUsername.text.trim(),
            password: _newPassword.text,
          )
        : null;
    setState(() => _isLaunching = true);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    unawaited(
      ref
          .read(installControllerProvider.notifier)
          .start(
            server: server,
            options: ref.read(installFormProvider),
            sshPassword: _password.text,
            newUser: newUser,
          ),
    );
    context.go(installProgressRoute);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // Keep the autoDispose advanced-options provider alive across the
    // Advanced screen round trip — without a live listener it would reset
    // to defaults before _startInstall reads it (same guard as the add
    // flow; review finding).
    ref.watch(installFormProvider);
    final serversAsync = ref.watch(serverListControllerProvider);
    final server = serversAsync.value
        ?.where((s) => s.id == widget.serverId)
        .firstOrNull;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.actionInstallWireguard)),
      body: server == null
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: ResponsiveContent(
                child: _form(context, l10n, server),
              ),
            ),
    );
  }

  Widget _form(BuildContext context, AppLocalizations l10n, Server server) {
    final isRootLogin = server.username == 'root';
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        children: [
          Text(
            '${server.username}@${server.host}:${server.sshPort}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.lg),
          AppTextField(
            label: l10n.fieldPassword,
            controller: _password,
            obscureText: true,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            validator: (value) => isValidLoginPassword(value ?? '')
                ? null
                : l10n.validationPassword,
          ),
          if (isRootLogin) ...[
            const SizedBox(height: AppSpacing.xl),
            AppBanner(
              variant: AppBannerVariant.warning,
              icon: Icons.warning_amber,
              title: l10n.sectionCreateUser,
              message: l10n.sectionCreateUserHint,
            ),
            const SizedBox(height: AppSpacing.md),
            AppTextField(
              label: l10n.fieldNewUsername,
              controller: _newUsername,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              validator: (value) => isValidNewUsername(value?.trim() ?? '')
                  ? null
                  : l10n.validationNewUsername,
            ),
            const SizedBox(height: AppSpacing.md),
            AppTextField(
              label: l10n.fieldNewPassword,
              controller: _newPassword,
              obscureText: true,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              validator: (value) => isValidNewPassword(value ?? '')
                  ? null
                  : l10n.validationNewPassword,
              helper:
                  _newPassword.text.isEmpty ||
                      !isValidNewPassword(_newPassword.text)
                  ? null
                  : PasswordStrengthBar(
                      strength: evaluatePasswordStrength(_newPassword.text),
                    ),
            ),
            const SizedBox(height: AppSpacing.md),
            AppTextField(
              label: l10n.fieldConfirmPassword,
              controller: _confirmPassword,
              obscureText: true,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              validator: (value) =>
                  passwordsMatch(_newPassword.text, value ?? '')
                  ? null
                  : l10n.validationConfirmPassword,
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          SecondaryButton(
            label: l10n.actionAdvanced,
            icon: Icons.tune,
            onPressed: () => context.push(advancedFormRoute),
          ),
          const SizedBox(height: AppSpacing.sm),
          PrimaryButton(
            label: l10n.actionInstallWireguard,
            icon: Icons.download,
            isLoading: _isLaunching,
            onPressed: _isLaunching
                ? null
                : () => unawaited(_startInstall(server)),
          ),
        ],
      ),
    );
  }
}
