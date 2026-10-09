import 'package:fav/l10n/app_localizations.dart';

/// Returns the localized label for an installer step identified by [key].
String installStepLabel(AppLocalizations l10n, String key) {
  return switch (key) {
    'probe' => l10n.stepProbe,
    'install_pkgs' => l10n.stepInstallPkgs,
    'create_user' => l10n.stepCreateUser,
    'deploy_app_key' => l10n.stepDeployAppKey,
    'generate_keys' => l10n.stepGenerateKeys,
    'write_server_conf' => l10n.stepWriteServerConf,
    'enable_forwarding' => l10n.stepEnableForwarding,
    'firewall' => l10n.stepFirewall,
    'start_service' => l10n.stepStartService,
    'hardening' => l10n.stepHardening,
    'health_check' => l10n.stepHealthCheck,
    'finalize' => l10n.stepFinalize,
    _ => key,
  };
}
