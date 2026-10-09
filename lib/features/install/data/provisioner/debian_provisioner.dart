import 'dart:convert';

import 'package:fav/core/errors/app_exception.dart';
import 'package:fav/core/utils/app_logger.dart';
import 'package:fav/core/utils/shell_quote.dart';
import 'package:fav/features/install/data/provisioner/config_env_writer.dart';
import 'package:fav/features/install/data/scripts/asset_script_repository.dart';
import 'package:fav/features/install/domain/advanced_options.dart';
import 'package:fav/features/install/domain/new_user_spec.dart';
import 'package:fav/features/install/domain/run_paths.dart';
import 'package:fav/features/install/domain/script_source.dart';
import 'package:fav/features/install/domain/ssh_client.dart';
import 'package:logger/logger.dart';

/// The launch command was sent, but its SSH reply was lost. The installer may
/// be running, so callers must preserve the run for remote reconciliation.
class ProvisioningLaunchUncertain implements Exception {
  /// Creates an uncertain-launch failure wrapping the transport error.
  const ProvisioningLaunchUncertain(this.cause);

  /// The transport failure raised while awaiting the launch reply.
  final Object cause;
}

/// Uploads the installer scripts to a server and launches them detached.
///
/// Implements the §7.2 sequence: create the run directory, SFTP-upload the
/// script set and the run parameters, then start the orchestrator under
/// `nohup`/`setsid` so it survives the SSH session closing.
class DebianProvisioner {
  /// Creates a [DebianProvisioner].
  ///
  /// [_client] must already be connected. [_bundle] is the *effective* script
  /// set the caller wants uploaded — the integrity-verified bundle with any
  /// user overrides already substituted (see `EffectiveScriptResolver`). The
  /// caller keeps ownership of [_client] and is responsible for closing it.
  DebianProvisioner({
    required this._client,
    required this._paths,
    required this._bundle,
    Logger? logger,
    this._configEnvWriter = const ConfigEnvWriter(),
  }) : _logger = logger ?? appLogger;

  final SshClient _client;
  final RunPaths _paths;
  final ScriptBundle _bundle;
  final Logger _logger;
  final ConfigEnvWriter _configEnvWriter;

  /// Provisions the server: upload the scripts and start the detached run.
  ///
  /// [sshPublicKey], when set, is the OpenSSH `authorized_keys` line for the
  /// app-generated Ed25519 key consumed unconditionally by
  /// `25_deploy_app_key` (M15-T1).
  ///
  /// Throws an [AppException] when a remote command fails.
  /// [sudoPassword] and [loginUser] are set when the SSH login is a non-root
  /// sudoer (root login disabled / never used): the run dir creation and the
  /// detached launch are then elevated with `sudo -S` (password via stdin),
  /// and the run dir is chowned to [loginUser] so the script/config uploads —
  /// which run as that user — can write into it. Both null for a root login.
  Future<void> start({
    required AdvancedOptions options,
    required String installationId,
    required String operationId,
    required String ipv6UlaSubnet,
    NewUserSpec? newUser,
    String? sshPublicKey,
    String? sudoPassword,
    String? loginUser,
    int sshPort = 22,
  }) async {
    _logger.i('Provisioning run ${_paths.runId}');
    try {
      await _createLayout(sudoPassword: sudoPassword, loginUser: loginUser);
      await _uploadScripts();
      await _uploadConfig(
        options: options,
        installationId: installationId,
        operationId: operationId,
        ipv6UlaSubnet: ipv6UlaSubnet,
        newUser: newUser,
        sshPublicKey: sshPublicKey,
        loginUser: loginUser,
        sshPort: sshPort,
      );
      await _launchDetached(sudoPassword: sudoPassword);
    } on ProvisioningLaunchUncertain {
      _logger.w('Provisioning launch outcome is uncertain');
      rethrow;
    } on Object catch (error) {
      // Surface the *actual* failure (the on-server orchestrator log is
      // empty when we fail before launch — only this Dart-side log helps).
      _logger.w('Provisioning failed: ${error.runtimeType}');
      // A failed launch must not leave config.env (with the password) on
      // disk: the orchestrator removes it only once it has started.
      try {
        await _client.run("rm -rf '${_paths.runDir}'");
      } on Object {
        _logger.w('Could not clean up the failed provisioning upload');
      }
      rethrow;
    }
    _logger.i('Run ${_paths.runId} launched detached');
  }

  Future<void> _createLayout({
    String? sudoPassword,
    String? loginUser,
  }) async {
    final dir = _paths.runDir;
    if (sudoPassword == null) {
      // Root login: it owns /opt and /var, and the uploads run as root too.
      await _runChecked(
        'mkdir -p '
            "'$dir/lib' '$dir/modules' "
            "'${RunPaths.stateDir}' '${RunPaths.logDir}' "
            "&& chmod 700 '$dir'",
        'create the run directory',
      );
      return;
    }
    // Non-root sudoer: create the root-owned dirs under sudo, then chown the
    // run dir to the login user so the subsequent uploads (which run as that
    // user) can write into it.
    final inner =
        "mkdir -p '$dir/lib' '$dir/modules' "
        "'${RunPaths.stateDir}' '${RunPaths.logDir}' "
        // -R so the sudo-created lib/ and modules/ subdirs are owned by the
        // login user too, otherwise the (non-sudo) uploads into them fail.
        "&& chown -R ${shellSingleQuote(loginUser ?? '')} '$dir' "
        "&& chmod 700 '$dir'";
    final result = await _client.run(
      "sudo -S -p '' -- bash -c ${shellSingleQuote(inner)}",
      stdin: '$sudoPassword\n',
    );
    if (!result.isSuccess) {
      _logger.w(
        'Step "create the run directory" failed via sudo '
        '(exit ${result.exitCode}); stderr: ${result.stderr.trim()}',
      );
      throw const AppException(
        ErrorCode.authNoSudo,
        detail: 'failed to create the run directory',
      );
    }
  }

  Future<void> _uploadScripts() async {
    for (final asset in _bundle.assets) {
      // The anti-lockout and hardening reviewed scripts ship in the bundle
      // but are uploaded later, from dedicated second SSH sessions, by
      // AntiLockoutService and HardeningService respectively. Same applies
      // to the monitoring agent assets (M15-T2): uploaded post-run by the
      // monitoring-install flow, never into the per-run script dir.
      if (asset.relativePath == kAntiLockoutScript ||
          asset.relativePath == kDisablePasswordAuthScript ||
          kMonitorBundleAssets.contains(asset.relativePath) ||
          kTeardownBundleAssets.contains(asset.relativePath)) {
        continue;
      }
      // Bytes are already the effective ones (overrides substituted upstream).
      await _client.uploadBytes(
        remotePath: _remotePathFor(asset.relativePath),
        data: asset.bytes,
      );
    }
  }

  Future<void> _uploadConfig({
    required AdvancedOptions options,
    required int sshPort,
    required String installationId,
    required String operationId,
    required String ipv6UlaSubnet,
    NewUserSpec? newUser,
    String? sshPublicKey,
    String? loginUser,
  }) async {
    final content = _configEnvWriter.render(
      options: options,
      installationId: installationId,
      operationId: operationId,
      ipv6UlaSubnet: ipv6UlaSubnet,
      newUser: newUser,
      sshPublicKey: sshPublicKey,
      loginUser: loginUser,
      sshPort: sshPort,
    );
    await _client.uploadBytes(
      remotePath: _paths.configPath,
      data: utf8.encode(content),
    );
    // Re-assert 0600 and read back the *actual* mode in one round trip, then
    // trust the verified mode — NOT chmod's exit status. dartssh2's exec
    // channel can report no exit code (-1) for a trivial command against
    // OpenSSH >= 10 even when it ran fine (the same quirk that forces the
    // base64-over-exec upload instead of SFTP). The file is already 0600 from
    // uploadBytes' `umask 077`; this verifies the security property that
    // matters — the password file must never be group/world readable — and a
    // missing file (silent upload failure) surfaces as a non-"600" mode too.
    final cfg = _paths.configPath;
    final verify = await _client.run(
      "chmod 600 '$cfg' 2>/dev/null; stat -c '%a' '$cfg' 2>/dev/null",
    );
    final mode = verify.stdout.trim();
    if (mode != '600') {
      _logger.w(
        'config.env is not mode 600 (got "$mode", exit ${verify.exitCode}); '
        'stderr: ${verify.stderr.trim()}',
      );
      // Never leave a readable file holding the password behind.
      await _client.run("rm -f '$cfg'");
      throw const AppException(
        ErrorCode.authNoSudo,
        detail: 'failed to restrict the run parameters file',
      );
    }
  }

  Future<void> _launchDetached({String? sudoPassword}) async {
    // nohup + setsid fully detach the installer from the SSH channel, so
    // closing the session does not terminate it (spec §7.1); the process id
    // is recorded for the recovery liveness check.
    final inner =
        "nohup setsid bash '${_paths.scriptPath}' </dev/null "
        "> '${_paths.logPath}' 2>&1 & echo \$! > '${_paths.pidPath}'";
    if (sudoPassword == null) {
      try {
        await _runChecked(inner, 'launch the installer');
      } on AppException {
        rethrow;
      } on Object catch (error) {
        throw ProvisioningLaunchUncertain(error);
      }
      return;
    }
    // Non-root sudoer: the installer needs root (it writes /etc, runs apt,
    // systemctl, …). sudo reads the password from stdin at launch and the
    // detached process inherits root; the password never reaches a command
    // line.
    final SshCommandResult result;
    try {
      result = await _client.run(
        "sudo -S -p '' -- bash -c ${shellSingleQuote(inner)}",
        stdin: '$sudoPassword\n',
      );
    } on Object catch (error) {
      throw ProvisioningLaunchUncertain(error);
    }
    if (!result.isSuccess) {
      _logger.w(
        'Step "launch the installer" failed via sudo '
        '(exit ${result.exitCode}); stderr: ${result.stderr.trim()}',
      );
      throw const AppException(
        ErrorCode.authNoSudo,
        detail: 'failed to launch the installer',
      );
    }
  }

  String _remotePathFor(String relativePath) {
    if (relativePath == 'install_wireguard.sh') {
      return _paths.scriptPath;
    }
    const libPrefix = 'lib/';
    if (relativePath.startsWith(libPrefix)) {
      return '${_paths.runDir}/$relativePath';
    }
    const modulesPrefix = 'modules/';
    if (relativePath.startsWith(modulesPrefix)) {
      return _paths.modulePath(relativePath.substring(modulesPrefix.length));
    }
    throw const AppException(
      ErrorCode.scriptInvalid,
      detail: 'unexpected bundled script path',
    );
  }

  Future<void> _runChecked(String command, String description) async {
    final result = await _client.run(command);
    if (!result.isSuccess) {
      // Log the failing command + exit code + stderr so the error is
      // diagnosable from the Dart log even when the orchestrator never
      // started (e.g. the failure was in _createLayout / _launchDetached).
      _logger.w(
        'Step "$description" failed (exit ${result.exitCode}).\n'
        'Command: $command\n'
        'Stderr: ${result.stderr.trim()}\n'
        'Stdout: ${result.stdout.trim()}',
      );
      throw AppException(
        ErrorCode.authNoSudo,
        detail: 'failed to $description',
      );
    }
  }
}
