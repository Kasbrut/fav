import 'package:fav/core/router/app_router.dart';
import 'package:fav/core/theme/app_dimens.dart';
import 'package:fav/core/utils/validators.dart';
import 'package:fav/core/widgets/app_banner.dart';
import 'package:fav/core/widgets/app_card.dart';
import 'package:fav/core/widgets/primary_button.dart';
import 'package:fav/core/widgets/responsive_content.dart';
import 'package:fav/core/widgets/section_header.dart';
import 'package:fav/features/install/application/install_form_controller.dart';
import 'package:fav/features/install/domain/advanced_options.dart';
import 'package:fav/features/servers/presentation/widgets/ssh_key_editor.dart';
import 'package:fav/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Screen to edit the advanced WireGuard options (RF-17, spec §9.1).
///
/// Parameters are presented as grouped settings rows (matching the design);
/// tapping a row opens a single-field edit dialog that validates the input.
class AdvancedFormScreen extends ConsumerStatefulWidget {
  /// Creates the advanced options screen.
  const AdvancedFormScreen({super.key});

  @override
  ConsumerState<AdvancedFormScreen> createState() => _AdvancedFormScreenState();
}

class _AdvancedFormScreenState extends ConsumerState<AdvancedFormScreen> {
  late final TextEditingController _wgPort;
  late final TextEditingController _subnet;
  late final TextEditingController _dns;
  late final TextEditingController _mtu;
  late final TextEditingController _interface;
  late final TextEditingController _endpoint;
  late bool _hardening;
  late bool _monitoring;
  late bool _backup;
  late List<String> _userKeys;

  @override
  void initState() {
    super.initState();
    final options = ref.read(installFormProvider);
    _wgPort = TextEditingController(text: '${options.wgPort}');
    _subnet = TextEditingController(text: options.vpnSubnet);
    _dns = TextEditingController(text: options.dns);
    _mtu = TextEditingController(text: '${options.mtu}');
    _interface = TextEditingController(text: options.interfaceName);
    _endpoint = TextEditingController(text: options.publicEndpoint ?? '');
    _hardening = options.enableHardening;
    _monitoring = options.enableMonitoring;
    _backup = options.backupExistingConfig;
    _userKeys = List<String>.of(options.userAuthorizedKeys);
  }

  @override
  void dispose() {
    _wgPort.dispose();
    _subnet.dispose();
    _dns.dispose();
    _mtu.dispose();
    _interface.dispose();
    _endpoint.dispose();
    super.dispose();
  }

  /// Builds the [AdvancedOptions] currently described by the form controls.
  ///
  /// Numeric fields fall back to the saved value if a controller is somehow
  /// empty, so this never throws even though the edit dialogs already validate.
  AdvancedOptions _currentOptions() {
    final saved = ref.read(installFormProvider);
    final endpoint = _endpoint.text.trim();
    return AdvancedOptions(
      wgPort: int.tryParse(_wgPort.text.trim()) ?? saved.wgPort,
      vpnSubnet: _subnet.text.trim(),
      dns: _dns.text.trim(),
      mtu: int.tryParse(_mtu.text.trim()) ?? saved.mtu,
      interfaceName: _interface.text.trim(),
      publicEndpoint: endpoint.isEmpty ? null : endpoint,
      enableHardening: _hardening,
      enableMonitoring: _monitoring,
      backupExistingConfig: _backup,
      userAuthorizedKeys: _userKeys,
    );
  }

  void _save(AppLocalizations l10n) {
    ref.read(installFormProvider.notifier).options = _currentOptions();
    // The messenger lives above this route, so the confirmation stays visible
    // after we pop back to the previous screen.
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(l10n.advancedOptionsSaved)));
    context.pop();
  }

  Future<void> _confirmRestoreDefaults(AppLocalizations l10n) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.restoreDefaultsConfirmTitle),
        content: Text(l10n.restoreDefaultsConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.actionRestoreDefaults),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    const defaults = AdvancedOptions();
    setState(() {
      _wgPort.text = '${defaults.wgPort}';
      _subnet.text = defaults.vpnSubnet;
      _dns.text = defaults.dns;
      _mtu.text = '${defaults.mtu}';
      _interface.text = defaults.interfaceName;
      _endpoint.text = '';
      _hardening = defaults.enableHardening;
      _monitoring = defaults.enableMonitoring;
      _backup = defaults.backupExistingConfig;
      _userKeys = List<String>.of(defaults.userAuthorizedKeys);
    });
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(l10n.restoreDefaultsDone)));
  }

  /// Asks the user to confirm leaving with unsaved edits. Returns `true` when
  /// the screen may be popped.
  Future<bool> _confirmDiscard(AppLocalizations l10n) async {
    final theme = Theme.of(context);
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.discardChangesTitle),
        content: Text(l10n.discardChangesBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.actionKeepEditing),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.error,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.actionDiscard),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  /// Opens a single-field edit dialog and writes the validated value back
  /// into [controller]. Editing is gated by [validator], so the values held
  /// by the controllers stay valid without a screen-wide form.
  Future<void> _editField({
    required String title,
    required TextEditingController controller,
    required FormFieldValidator<String> validator,
    TextInputType? keyboardType,
    String? initialValue,
    String? suffixText,
    String Function(String)? resultTransform,
  }) async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) => _EditFieldDialog(
        title: title,
        initialValue: initialValue ?? controller.text,
        validator: validator,
        keyboardType: keyboardType,
        suffixText: suffixText,
      ),
    );
    if (result != null && mounted) {
      setState(() => controller.text = resultTransform?.call(result) ?? result);
    }
  }

  /// Opens the add-key dialog and appends the result to the in-memory list.
  /// No SSH here — the keys are deployed during the install run by
  /// `26_deploy_user_keys`.
  Future<void> _addKey(AppLocalizations l10n) async {
    final line = await showAddSshKeyDialog(context);
    if (line == null || !mounted) {
      return;
    }
    if (_userKeys.contains(line)) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l10n.sshKeyDuplicate)));
      return;
    }
    setState(() => _userKeys = [..._userKeys, line]);
  }

  void _removeKey(String line) {
    setState(() => _userKeys = _userKeys.where((k) => k != line).toList());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final endpoint = _endpoint.text.trim();
    final saved = ref.watch(installFormProvider);
    final isDirty = _currentOptions() != saved;
    return PopScope(
      canPop: !isDirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final shouldDiscard = await _confirmDiscard(l10n);
        if (shouldDiscard && context.mounted) context.pop();
      },
      child: Scaffold(
        appBar: AppBar(title: Text(l10n.advancedFormTitle)),
        body: ResponsiveContent(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.xxl,
            ),
            children: [
              SectionHeader(
                label: l10n.advancedSectionWireguard,
                hint: l10n.advancedSectionWireguardHint,
              ),
              const SizedBox(height: AppSpacing.sm),
              AppCard(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: Column(
                  children: [
                    _SettingRow(
                      label: l10n.fieldWgPort,
                      value: _wgPort.text,
                      onTap: () => _editField(
                        title: l10n.fieldWgPort,
                        controller: _wgPort,
                        keyboardType: TextInputType.number,
                        validator: (value) => isValidPort(value?.trim() ?? '')
                            ? null
                            : l10n.validationPort,
                      ),
                    ),
                    const Divider(height: 1),
                    _SettingRow(
                      label: l10n.fieldVpnSubnet,
                      value: _subnet.text,
                      onTap: () => _editField(
                        title: l10n.fieldVpnSubnet,
                        controller: _subnet,
                        initialValue: _subnet.text.replaceFirst('/24', ''),
                        suffixText: '/24',
                        resultTransform: (value) => '$value/24',
                        validator: (value) =>
                            isValidVpnSubnet('${value?.trim() ?? ''}/24')
                            ? null
                            : l10n.validationSubnet,
                      ),
                    ),
                    const Divider(height: 1),
                    _SettingRow(
                      label: l10n.fieldDns,
                      value: _dns.text,
                      onTap: () => _editField(
                        title: l10n.fieldDns,
                        controller: _dns,
                        validator: (value) =>
                            isValidDnsList(value?.trim() ?? '')
                            ? null
                            : l10n.validationDns,
                      ),
                    ),
                    const Divider(height: 1),
                    _SettingRow(
                      label: l10n.fieldMtu,
                      value: _mtu.text,
                      onTap: () => _editField(
                        title: l10n.fieldMtu,
                        controller: _mtu,
                        keyboardType: TextInputType.number,
                        validator: (value) => isValidMtu(value?.trim() ?? '')
                            ? null
                            : l10n.validationMtu,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              SectionHeader(
                label: l10n.advancedSectionNetwork,
                hint: l10n.advancedSectionNetworkHint,
              ),
              const SizedBox(height: AppSpacing.sm),
              AppCard(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: Column(
                  children: [
                    _SettingRow(
                      label: l10n.fieldInterfaceName,
                      value: _interface.text,
                      onTap: () => _editField(
                        title: l10n.fieldInterfaceName,
                        controller: _interface,
                        validator: (value) =>
                            isValidInterfaceName(value?.trim() ?? '')
                            ? null
                            : l10n.validationInterfaceName,
                      ),
                    ),
                    const Divider(height: 1),
                    _SettingRow(
                      label: l10n.fieldPublicEndpoint,
                      value: endpoint.isEmpty ? l10n.valueNotSet : endpoint,
                      muted: endpoint.isEmpty,
                      onTap: () => _editField(
                        title: l10n.fieldPublicEndpoint,
                        controller: _endpoint,
                        validator: (value) {
                          final text = value?.trim() ?? '';
                          return text.isEmpty || isValidHostOrIp(text)
                              ? null
                              : l10n.validationPublicEndpoint;
                        },
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              SectionHeader(
                label: l10n.advancedSectionOptions,
                hint: l10n.advancedSectionOptionsHint,
              ),
              const SizedBox(height: AppSpacing.sm),
              AppCard(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: Column(
                  children: [
                    _SwitchRow(
                      label: l10n.fieldEnableHardening,
                      description: l10n.fieldEnableHardeningDescription,
                      value: _hardening,
                      onChanged: (value) => setState(() => _hardening = value),
                    ),
                    const Divider(height: 1),
                    _SwitchRow(
                      label: l10n.fieldEnableMonitoring,
                      description: l10n.fieldEnableMonitoringDescription,
                      value: _monitoring,
                      onChanged: (value) => setState(() => _monitoring = value),
                    ),
                    const Divider(height: 1),
                    _SwitchRow(
                      label: l10n.fieldBackupConfig,
                      description: l10n.fieldBackupConfigDescription,
                      value: _backup,
                      onChanged: (value) => setState(() => _backup = value),
                    ),
                  ],
                ),
              ),
              // Hardening changes how the user logs in, so the
              // lockout-protection promise (spec §10.2) is shown plainly the
              // moment it is enabled.
              _HardeningNotice(visible: _hardening),
              const SizedBox(height: AppSpacing.lg),
              SectionHeader(
                label: l10n.sshKeysSectionTitle,
                hint: l10n.sshKeysSectionHint,
              ),
              const SizedBox(height: AppSpacing.sm),
              SshKeyListCard(
                keys: _userKeys,
                onAdd: () => _addKey(l10n),
                onRemove: _removeKey,
              ),
              const SizedBox(height: AppSpacing.xl),
              PrimaryButton(
                label: l10n.actionSave,
                onPressed: () => _save(l10n),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextButton(
                onPressed: () => _confirmRestoreDefaults(l10n),
                child: Text(l10n.actionRestoreDefaults),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A single-field edit dialog that owns its [TextEditingController].
///
/// The controller is owned (and disposed) by this widget's state rather than
/// the caller, so it is released only after the dialog route is fully gone —
/// avoiding a use-after-dispose during the dialog's exit animation.
class _EditFieldDialog extends StatefulWidget {
  const _EditFieldDialog({
    required this.title,
    required this.initialValue,
    required this.validator,
    this.keyboardType,
    this.suffixText,
  });

  /// The dialog title and edited parameter name.
  final String title;

  /// The value shown when the dialog opens.
  final String initialValue;

  /// Validator that gates confirmation.
  final FormFieldValidator<String> validator;

  /// Keyboard type for the input.
  final TextInputType? keyboardType;

  /// Fixed text rendered after the editable value.
  final String? suffixText;

  @override
  State<_EditFieldDialog> createState() => _EditFieldDialogState();
}

class _EditFieldDialogState extends State<_EditFieldDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState?.validate() ?? false) {
      Navigator.of(context).pop(_controller.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(widget.title),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _controller,
          autofocus: true,
          keyboardType: widget.keyboardType,
          decoration: InputDecoration(suffixText: widget.suffixText),
          validator: widget.validator,
          // Re-validate as the user types so the error clears the moment the
          // value becomes valid, matching the add-server form.
          autovalidateMode: AutovalidateMode.onUserInteraction,
          onFieldSubmitted: (_) => _submit(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.actionCancel),
        ),
        FilledButton(onPressed: _submit, child: Text(l10n.actionConfirm)),
      ],
    );
  }
}

/// A tappable settings row showing [label] on the left and [value] on the
/// right, with a trailing chevron — the editable rows of the design's cards.
class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.label,
    required this.value,
    required this.onTap,
    this.muted = false,
  });

  /// The parameter caption.
  final String label;

  /// The current parameter value, shown right-aligned.
  final String value;

  /// Called when the row is tapped to edit the value.
  final VoidCallback onTap;

  /// Whether [value] is a placeholder (e.g. an unset optional field).
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppSizes.minTouchTarget),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          // Label hugs the left; the value and chevron hug the right, with the
          // free space between them. The trailing group keeps the chevrons on a
          // single right margin regardless of how short the label or value is.
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.md),
                  child: Text(
                    label,
                    style: theme.textTheme.bodyMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              Flexible(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        value,
                        textAlign: TextAlign.end,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        // Values read as data (ink), matching DetailRow and
                        // keeping the One Accent Rule: blue stays reserved for
                        // the Save action. Unset placeholders stay muted.
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: muted
                              ? theme.colorScheme.onSurfaceVariant
                              : theme.colorScheme.onSurface,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Icon(
                      Icons.chevron_right,
                      size: 18,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A settings row pairing [label] (and an optional [description]) with a
/// trailing [Switch].
class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.label,
    required this.value,
    required this.onChanged,
    this.description,
  });

  /// The option caption.
  final String label;

  /// Optional one-line plain-language explanation shown under [label].
  final String? description;

  /// Whether the option is currently enabled.
  final bool value;

  /// Called when the option is toggled.
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Merge the label, description and Switch into one node so a screen reader
    // announces "<label>, <description>, switch, on/off" as a single control.
    return MergeSemantics(
      child: InkWell(
        onTap: () => onChanged(!value),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppSizes.minTouchTarget),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: theme.textTheme.bodyMedium),
                      if (description != null) ...[
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          description!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Switch(value: value, onChanged: onChanged),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A warning callout that explains the anti-lockout guarantees behind SSH
/// hardening (spec §10.2), revealed when the option is enabled.
class _HardeningNotice extends StatelessWidget {
  const _HardeningNotice({required this.visible});

  /// Whether the notice should be shown.
  final bool visible;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // Honour the OS "reduce motion" setting: animate the reveal otherwise.
    final duration = MediaQuery.of(context).disableAnimations
        ? Duration.zero
        : const Duration(milliseconds: 200);
    return AnimatedSize(
      duration: duration,
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: visible
          ? Padding(
              padding: const EdgeInsets.only(top: AppSpacing.md),
              child: AppBanner(
                variant: AppBannerVariant.warning,
                icon: Icons.gpp_good_outlined,
                title: l10n.advancedHardeningNoticeTitle,
                message: l10n.advancedHardeningNoticeBody,
                action: TextButton.icon(
                  onPressed: () =>
                      context.push(glossaryEntryPath('ssh-hardening')),
                  icon: const Icon(Icons.info_outline, size: 18),
                  label: Text(l10n.advancedHardeningLearnMore),
                ),
              ),
            )
          : const SizedBox(width: double.infinity),
    );
  }
}
