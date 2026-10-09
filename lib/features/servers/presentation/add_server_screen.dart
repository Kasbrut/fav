import 'dart:async';

import 'package:fav/core/errors/error_messages.dart';
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
import 'package:fav/core/widgets/section_header.dart';
import 'package:fav/features/help/application/recent_errors_provider.dart';
import 'package:fav/features/help/presentation/error_help_link.dart';
import 'package:fav/features/install/application/install_controller.dart';
import 'package:fav/features/install/application/install_form_controller.dart';
import 'package:fav/features/install/domain/new_user_spec.dart';
import 'package:fav/features/install/domain/ssh_client.dart';
import 'package:fav/features/servers/application/add_server_controller.dart';
import 'package:fav/features/servers/domain/host_key_fingerprint.dart';
import 'package:fav/features/servers/domain/server.dart';
import 'package:fav/features/servers/presentation/widgets/host_key_dialog.dart';
import 'package:fav/features/settings/application/preferences_controller.dart';
import 'package:fav/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Screen to add a server and start its installation (spec §6.1).
class AddServerScreen extends ConsumerStatefulWidget {
  /// Creates the add-server screen.
  const AddServerScreen({this.retryServer, super.key});

  /// Server whose failed provisioning is being retried.
  final Server? retryServer;

  @override
  ConsumerState<AddServerScreen> createState() => _AddServerScreenState();
}

class _AddServerScreenState extends ConsumerState<AddServerScreen> {
  final _formKey = GlobalKey<FormState>();
  final _label = TextEditingController();
  final _host = TextEditingController();
  final _port = TextEditingController(text: '22');
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _newUsername = TextEditingController();
  final _newPassword = TextEditingController();
  final _confirmPassword = TextEditingController();
  late bool _connectionLocked;

  @override
  void initState() {
    super.initState();
    final retryServer = widget.retryServer;
    _connectionLocked = retryServer != null;
    if (retryServer != null) {
      _label.text = retryServer.label;
      _host.text = retryServer.host;
      _port.text = retryServer.sshPort.toString();
      _username.text = retryServer.username;
    }
    _username.addListener(_onFieldsChanged);
    _newPassword.addListener(_onFieldsChanged);
  }

  @override
  void dispose() {
    _username.removeListener(_onFieldsChanged);
    _newPassword.removeListener(_onFieldsChanged);
    _label.dispose();
    _host.dispose();
    _port.dispose();
    _username.dispose();
    _newUsername.dispose();
    // Best-effort: drop the password text before releasing the controllers.
    for (final controller in [_password, _newPassword, _confirmPassword]) {
      controller
        ..clear()
        ..dispose();
    }
    super.dispose();
  }

  void _onFieldsChanged() => setState(() {});

  bool get _isRootLogin => _username.text.trim() == 'root';

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    if (_isRootLogin &&
        evaluatePasswordStrength(_newPassword.text) == PasswordStrength.weak) {
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.errPasswordTooWeak)),
      );
      return;
    }
    // Drop the field focus before opening the host-key dialog. Otherwise
    // Flutter restores the previously focused field when the dialog closes
    // and the software keyboard reappears behind the loading state.
    FocusManager.instance.primaryFocus?.unfocus();
    await ref
        .read(addServerControllerProvider.notifier)
        .submit(
          label: _label.text.trim(),
          params: SshConnectionParams(
            host: _host.text.trim(),
            port: int.parse(_port.text.trim()),
            username: _username.text.trim(),
            password: _password.text,
          ),
        );
  }

  Future<void> _handleHostKey(
    HostKeyFingerprint fingerprint, {
    required bool previouslyTrusted,
  }) async {
    final controller = ref.read(addServerControllerProvider.notifier);
    final trusted = await showHostKeyDialog(
      context,
      fingerprint,
      previouslyTrusted: previouslyTrusted,
    );
    if (!mounted) return;
    FocusManager.instance.primaryFocus?.unfocus();
    if (trusted ?? false) {
      await controller.confirmHostKey();
      await _submit();
    } else {
      controller.cancelHostKey();
    }
  }

  void _startInstall(Server server) {
    final newUser = _isRootLogin
        ? NewUserSpec(
            username: _newUsername.text.trim(),
            password: _newPassword.text,
          )
        : null;
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

  void _onStateChanged(AddServerState? previous, AddServerState next) {
    final l10n = AppLocalizations.of(context)!;
    switch (next) {
      case AddServerHostKeyPending(
        :final fingerprint,
        :final previouslyTrusted,
      ):
        unawaited(
          _handleHostKey(fingerprint, previouslyTrusted: previouslyTrusted),
        );
      case AddServerSuccess(:final server):
        _startInstall(server);
      case AddServerFailure(:final code):
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
      case AddServerEditing():
      case AddServerConnecting():
      case AddServerProbing():
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(addServerControllerProvider);
    // Keep the advanced-options provider alive across the Advanced screen.
    ref
      ..watch(installFormProvider)
      ..listen(addServerControllerProvider, _onStateChanged);

    final busy = state is AddServerConnecting || state is AddServerProbing;

    return Scaffold(
      appBar: AppBar(
        leading: widget.retryServer == null
            ? null
            : IconButton(
                tooltip: l10n.actionBackToServers,
                icon: const Icon(Icons.arrow_back),
                onPressed: () => context.go(serverListRoute),
              ),
        title: Text(l10n.addServerTitle),
      ),
      body: AbsorbPointer(
        absorbing: busy,
        child: ResponsiveContent(
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.xxl,
              ),
              children: [
                AppTextField(
                  label: l10n.fieldServerName,
                  controller: _label,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  validator: (value) => isValidServerLabel(value?.trim() ?? '')
                      ? null
                      : l10n.validationServerName,
                ),
                const SizedBox(height: AppSpacing.md),
                _hostAndPortField(l10n),
                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  label: l10n.fieldUsername,
                  controller: _username,
                  enabled: !_connectionLocked,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  validator: (value) =>
                      isValidLoginUsername(value?.trim() ?? '')
                      ? null
                      : l10n.validationUsername,
                ),
                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  label: l10n.fieldPassword,
                  controller: _password,
                  obscureText: true,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  validator: (value) => isValidLoginPassword(value ?? '')
                      ? null
                      : l10n.validationPassword,
                ),
                if (_isRootLogin) ..._nonRootSection(l10n),
                const SizedBox(height: AppSpacing.lg),
                if (_connectionLocked) ...[
                  SecondaryButton(
                    label: l10n.actionEditConnection,
                    icon: Icons.edit_outlined,
                    onPressed: () => setState(() => _connectionLocked = false),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
                SecondaryButton(
                  label: l10n.actionAdvanced,
                  icon: Icons.tune,
                  onPressed: () => context.push(advancedFormRoute),
                ),
                const SizedBox(height: AppSpacing.sm),
                PrimaryButton(
                  label: l10n.actionConnectInstall,
                  onPressed: busy ? null : _submit,
                  isLoading: busy,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Host and SSH port on a single row, sharing one caption (matches design).
  Widget _hostAndPortField(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(label: l10n.fieldHostAndPort),
        const SizedBox(height: AppSpacing.sm),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: Semantics(
                textField: true,
                label: l10n.fieldHost,
                child: TextFormField(
                  controller: _host,
                  enabled: !_connectionLocked,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  decoration: InputDecoration(
                    hintText: l10n.fieldHostHint,
                    helperText: l10n.fieldHostHelper,
                  ),
                  validator: (value) => isValidHostOrIp(value?.trim() ?? '')
                      ? null
                      : l10n.validationHost,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Semantics(
                textField: true,
                label: l10n.fieldSshPort,
                child: TextFormField(
                  controller: _port,
                  enabled: !_connectionLocked,
                  keyboardType: TextInputType.number,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  validator: (value) => isValidPort(value?.trim() ?? '')
                      ? null
                      : l10n.validationPort,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  List<Widget> _nonRootSection(AppLocalizations l10n) {
    return [
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
        validator: (value) =>
            isValidNewPassword(value ?? '') ? null : l10n.validationNewPassword,
        // Until the policy is satisfied, the field's single validation
        // message explains the requirements. Showing a green strength bar at
        // the same time would be contradictory for short but complex values.
        helper:
            _newPassword.text.isEmpty || !isValidNewPassword(_newPassword.text)
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
        validator: (value) => passwordsMatch(_newPassword.text, value ?? '')
            ? null
            : l10n.validationConfirmPassword,
      ),
    ];
  }
}
