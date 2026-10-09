import 'dart:async';

import 'package:fav/core/crypto/ed25519_keypair.dart';
import 'package:fav/core/errors/app_exception.dart';
import 'package:fav/core/utils/app_logger.dart';
import 'package:fav/core/utils/ipv6.dart';
import 'package:fav/core/utils/shell_quote.dart';
import 'package:fav/features/install/application/anti_lockout_service.dart';
import 'package:fav/features/install/application/hardening_service.dart';
import 'package:fav/features/install/application/monitoring_install_service.dart';
import 'package:fav/features/install/application/run_polling_controller.dart';
import 'package:fav/features/install/application/run_recovery_provider.dart';
import 'package:fav/features/install/application/services_teardown_service.dart';
import 'package:fav/features/install/application/ssh_auth_resolver.dart';
import 'package:fav/features/install/application/wireguard_port_reachability_service.dart';
import 'package:fav/features/install/data/hive_run_repository.dart';
import 'package:fav/features/install/data/keys/ssh_key_repository.dart';
import 'package:fav/features/install/data/provisioner/debian_provisioner.dart';
import 'package:fav/features/install/data/provisioner/network_result_parser.dart';
import 'package:fav/features/install/data/provisioner/run_state_parser.dart';
import 'package:fav/features/install/data/provisioner/wireguard_probe.dart';
import 'package:fav/features/install/data/scripts/asset_script_repository.dart';
import 'package:fav/features/install/data/scripts/effective_script_resolver.dart';
import 'package:fav/features/install/data/ssh/dart_ssh_client.dart';
import 'package:fav/features/install/data/ssh/ssh_error_mapper.dart';
import 'package:fav/features/install/domain/advanced_options.dart';
import 'package:fav/features/install/domain/install_run.dart';
import 'package:fav/features/install/domain/install_step.dart';
import 'package:fav/features/install/domain/management_identity.dart';
import 'package:fav/features/install/domain/new_user_spec.dart';
import 'package:fav/features/install/domain/run_paths.dart';
import 'package:fav/features/install/domain/script_source.dart';
import 'package:fav/features/install/domain/ssh_client.dart';
import 'package:fav/features/peers/data/hive_peer_repository.dart';
import 'package:fav/features/peers/data/secure_peer_secret_repository.dart';
import 'package:fav/features/peers/domain/peer.dart';
import 'package:fav/features/profile/data/client_profile_parser.dart';
import 'package:fav/features/profile/domain/client_profile.dart';
import 'package:fav/features/servers/application/server_list_controller.dart';
import 'package:fav/features/servers/data/hive_server_repository.dart';
import 'package:fav/features/servers/domain/server.dart';
import 'package:fav/features/servers/domain/wireguard_installation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';
import 'package:uuid/uuid.dart';

/// State of the end-to-end installation flow (spec §6.1).
@immutable
sealed class InstallFlowState {
  /// Const base constructor.
  const InstallFlowState();
}

/// No installation has been started.
class InstallIdle extends InstallFlowState {
  /// Creates an [InstallIdle].
  const InstallIdle();
}

/// Connecting, verifying script integrity and uploading.
class InstallPreparing extends InstallFlowState {
  /// Creates an [InstallPreparing].
  const InstallPreparing();
}

/// An existing WireGuard installation was detected; awaiting confirmation.
class InstallNeedsConfirmation extends InstallFlowState {
  /// Creates an [InstallNeedsConfirmation].
  const InstallNeedsConfirmation(this.server);

  /// The target server, which already carries a WireGuard installation.
  final Server server;
}

/// The installer runs detached on the server and is being polled.
class InstallRunning extends InstallFlowState {
  /// Creates an [InstallRunning].
  const InstallRunning(this.run);

  /// The run as created; live progress comes from the polling controller.
  final InstallRun run;
}

/// The install succeeded and root SSH is being disabled (anti-lockout).
class InstallAntiLockout extends InstallFlowState {
  /// Creates an [InstallAntiLockout].
  const InstallAntiLockout(this.run);

  /// The completed run.
  final InstallRun run;
}

/// The install succeeded and SSH password authentication is being disabled
/// (optional hardening, spec §10.3).
class InstallHardening extends InstallFlowState {
  /// Creates an [InstallHardening].
  const InstallHardening(this.run);

  /// The completed run.
  final InstallRun run;
}

/// The installation finished successfully.
class InstallSuccess extends InstallFlowState {
  /// Creates an [InstallSuccess].
  const InstallSuccess({
    required this.run,
    required this.rootSshDisabled,
    required this.hardeningApplied,
    required this.monitoringInstalled,
    this.configBackupPath,
    this.lockoutWarning,
    this.hardeningWarning,
    this.monitoringWarning,
  });

  /// The completed run.
  final InstallRun run;

  /// Whether root SSH login was disabled.
  final bool rootSshDisabled;

  /// Whether the optional SSH hardening was applied (password auth disabled).
  final bool hardeningApplied;

  /// Whether the WireGuard peer monitoring agent was installed (M15-T7).
  final bool monitoringInstalled;

  /// Path of the pre-existing configuration backup, if one was made.
  final String? configBackupPath;

  /// Set when the anti-lockout sequence aborted (root SSH left enabled).
  final AppException? lockoutWarning;

  /// Set when the hardening sequence aborted (password auth left enabled).
  final AppException? hardeningWarning;

  /// Set when the monitoring-install step aborted; surfaced as a warning
  /// since monitoring is non-critical (the install itself succeeded).
  final AppException? monitoringWarning;
}

/// The installation failed.
class InstallFailure extends InstallFlowState {
  /// Creates an [InstallFailure].
  const InstallFailure({required this.error, this.run, this.failedStepKey});

  /// The failure to surface to the user.
  final AppException error;

  /// The run at the moment of failure, when one had started.
  final InstallRun? run;

  /// Key of the step that failed, when known.
  final String? failedStepKey;
}

/// Orchestrates the install: connect, provision, poll, anti-lockout (§6.1).
class InstallController extends Notifier<InstallFlowState> {
  late Server _server;
  late AdvancedOptions _options;
  late RunPaths _paths;

  /// Mirror of [_paths] that is null until a run was actually prepared on
  /// the server — [_paths] is `late`, so a pre-launch failure (integrity,
  /// probe) would throw on access. Lets [reset] know whether there is
  /// anything to clean up (audit F5).
  RunPaths? _launchedPaths;
  late EffectiveScriptResolver _resolver;
  late ScriptBundle _bundle;
  String _sshPassword = '';
  NewUserSpec? _newUser;

  /// App-generated Ed25519 keypair deployed on every install (M15-T1).
  /// The seed lives in the secure store; this field is only the in-memory
  /// reference for the current install and is cleared in [_finalizeSuccess].
  Ed25519KeyPair? _appKeyPair;
  String? _sshPublicKey;
  bool _wantsHardening = false;
  bool _cancelled = false;
  InstallRun? _pendingRun;

  /// Management username restored from a recovered run — set only when the
  /// matching app key pair still exists locally (M3): finalize then records
  /// this account + `sshKeyId` instead of the resume login, so key-only
  /// operations (monitoring above all) keep working after a recovery.
  String? _recoveredManagement;

  /// Base64 runs of key length in the fetched run log — a user-edited
  /// module could cat key material into it (audit M3).
  static final RegExp _keyLikeBase64 = RegExp('[A-Za-z0-9+/]{40,}={0,2}');

  /// Failure surfaced when the user cancels; also used by the phase-boundary
  /// aborts during Preparing (audit M4).
  static const AppException _cancelledError = AppException(
    ErrorCode.runStepFailed,
    detail: 'installation cancelled',
  );

  @override
  InstallFlowState build() {
    // Debug visibility over the whole flow: every transition is logged with
    // the fields that matter for diagnosis (run id, failed step, error code).
    // AppException.detail is already sanitized at the throw sites (§10.1) and
    // the redacting printer is a second net.
    listenSelf(
      (previous, next) =>
          ref.read(loggerProvider).i('Install state: ${_describe(next)}'),
    );
    return const InstallIdle();
  }

  static String _describe(InstallFlowState state) => switch (state) {
    InstallRunning(:final run) => 'InstallRunning(run=${run.runId})',
    InstallFailure(:final error) =>
      'InstallFailure(${error.code.name}${_sanitizedDetail(error.detail)})',
    _ => state.runtimeType.toString(),
  };

  /// Makes a failure detail safe to log: `detail` can carry remote-controlled
  /// text (the state file's `error` field), so collapse whitespace to keep it
  /// on one non-forgeable line, redact secret-looking values and cap the
  /// length. Sanitizing here makes the log safe by construction instead of by
  /// convention at the throw sites.
  static String _sanitizedDetail(String? detail) {
    if (detail == null) return '';
    var line = redactSecrets(detail.replaceAll(RegExp(r'\s+'), ' '));
    if (line.length > 120) line = '${line.substring(0, 120)}…';
    return ': $line';
  }

  /// Whether a new flow may begin: only from idle or a terminal state.
  /// Mid-flight, a second [start]/[attachRecovered] would clobber the live
  /// run's fields and leak its SSH client (audit M2).
  bool get _flowIdle => switch (state) {
    InstallIdle() || InstallFailure() || InstallSuccess() => true,
    _ => false,
  };

  /// Connection data used to prefill a fresh attempt after a failure.
  Server? get retryServer => _server;

  /// Runs the full installation for [server] with the given options.
  ///
  /// [sshPassword] and [newUser]'s password are transient — never persisted.
  /// Refused (no-op) while another flow is in flight (audit M2).
  Future<void> start({
    required Server server,
    required AdvancedOptions options,
    required String sshPassword,
    NewUserSpec? newUser,
  }) async {
    if (!_flowIdle) {
      ref
          .read(loggerProvider)
          .w('start refused: another install flow is in flight');
      return;
    }
    _server = server;
    // Defensive: never let a previous run's paths outlive it into this one.
    _launchedPaths = null;
    // When the user has not set a public endpoint in Advanced, fall back to
    // the host they typed when adding the server. Without this the
    // orchestrator's `99_finalize.sh` would write `Endpoint = :<port>` (no
    // host) into client.conf — the QR would parse but no client could
    // connect (M14 smoke test 2026-05-21, run 783767f8).
    _options =
        (options.publicEndpoint == null || options.publicEndpoint!.isEmpty)
        ? options.copyWith(publicEndpoint: server.host)
        : options;
    _sshPassword = sshPassword;
    _newUser = newUser;
    // SSH hardening (disable root SSH + disable password auth + fail2ban) is
    // governed solely by the hardening switch and applies to whichever user the
    // app manages the server as — the created user (root login) or the login
    // user (non-root sudoer). It is NOT tied to creating a new user.
    _wantsHardening = _options.enableHardening;
    _appKeyPair = null;
    _recoveredManagement = null;
    _cancelled = false;
    state = const InstallPreparing();

    // M15-T1: generate (or load) the app's Ed25519 keypair for every install,
    // not only when hardening is enabled. The public key flows into the
    // installer via SSH_PUBKEY and the dedicated step `25_deploy_app_key`
    // authorizes it on the login user. Server.sshKeyId is set in
    // _finalizeSuccess so post-install operations authenticate by key.
    _appKeyPair = await ref
        .read(sshKeyRepositoryProvider)
        .getOrCreate(
          serverId: server.id,
          comment: 'fav@${server.id}',
        );
    _sshPublicKey = _appKeyPair!.authorizedKeysEntry(
      comment: 'fav@${server.id}',
    );

    // Resolve the effective scripts (integrity-verified bundle + any global
    // user overrides). The hash and `scriptWasModified` flag of what is
    // actually uploaded are carried through into the run record.
    final EffectiveScriptResolver resolver;
    final ScriptBundle bundle;
    final bool scriptWasModified;
    try {
      resolver = await ref.read(effectiveScriptResolverProvider.future);
      bundle = await resolver.effectiveBundle();
      // Scope the "modified" flag to the install bundle so it stays consistent
      // with scriptContentHash (peer-only overrides don't affect an install).
      scriptWasModified =
          bundle.bundleHash != resolver.pristineBundle.bundleHash;
    } on Object {
      state = const InstallFailure(
        error: AppException(ErrorCode.scriptInvalid),
      );
      return;
    }
    _resolver = resolver;
    _bundle = bundle;

    final paths = RunPaths.generate();
    _paths = paths;
    _launchedPaths = paths;
    final run = _buildInitialRun(server, paths, bundle, scriptWasModified);

    final client = ref.read(sshClientFactoryProvider)();
    try {
      await client.connect(await _paramsFor(server, password: sshPassword));
    } on HostKeyUnknownException {
      await client.close();
      state = const InstallFailure(
        error: AppException(ErrorCode.hostKeyMismatch),
      );
      return;
    } on AppException catch (error) {
      // No `run` on any connect failure: nothing was created on the server,
      // so there is no remote log to offer (audit F11).
      await client.close();
      state = InstallFailure(error: error);
      return;
    } on Object {
      await client.close();
      state = const InstallFailure(
        error: AppException(ErrorCode.connHostUnreachable),
      );
      return;
    }

    // Cancel is cooperative during Preparing (audit M4): honour it at each
    // phase boundary so nothing further runs on the server. No `run` on the
    // failure — the detached run never started, so there is no remote log.
    if (_cancelled) {
      await client.close();
      state = const InstallFailure(error: _cancelledError);
      return;
    }

    final bool alreadyInstalled;
    try {
      alreadyInstalled = await ref
          .read(wireguardProbeProvider)
          .isWireguardInstalled(client);
    } on AppException catch (error) {
      await client.close();
      state = InstallFailure(error: error);
      return;
    } on Object catch (error) {
      await client.close();
      state = InstallFailure(error: AppException(mapSshError(error)));
      return;
    }
    if (_cancelled) {
      await client.close();
      state = const InstallFailure(error: _cancelledError);
      return;
    }
    if (alreadyInstalled) {
      // Do not hold the SSH connection across the confirmation dialog;
      // confirmReinstall() reconnects freshly.
      await client.close();
      _pendingRun = run;
      state = InstallNeedsConfirmation(server);
      return;
    }
    await _proceedWithInstall(client, run);
  }

  /// Confirms a reinstall after an existing installation was detected.
  Future<void> confirmReinstall() async {
    final run = _pendingRun;
    if (state is! InstallNeedsConfirmation || run == null) {
      return;
    }
    _pendingRun = null;
    state = const InstallPreparing();
    final client = ref.read(sshClientFactoryProvider)();
    try {
      await client.connect(
        await _paramsFor(_server, password: _passwordForResume()),
      );
    } on AppException catch (error) {
      // No `run` on a connect failure — see start() (audit F11).
      await client.close();
      state = InstallFailure(error: error);
      return;
    } on Object {
      await client.close();
      state = const InstallFailure(
        error: AppException(ErrorCode.connHostUnreachable),
      );
      return;
    }
    await _proceedWithInstall(client, run);
  }

  /// Resumes polling a run recovered after the app was reopened (spec §6.4).
  ///
  /// The anti-lockout phase is not re-run: the new user's password is not
  /// available on recovery. [sshPassword] is `null` when the server uses
  /// key-based auth (post-hardening); the controller keeps it as an empty
  /// string and the auth resolver picks the key automatically.
  Future<void> attachRecovered({
    required SshClient client,
    required InstallRun run,
    required RunPaths paths,
    required Server server,
    String? sshPassword,
  }) async {
    if (!_flowIdle) {
      // Refused mid-flow (audit M2): release the recovered connection — the
      // caller handed over ownership, so returning without closing leaks it.
      ref
          .read(loggerProvider)
          .w('attachRecovered refused: another install flow is in flight');
      await client.close();
      return;
    }
    _server = server;
    // Restore the options the run was actually launched with (audit M3);
    // legacy records without them fall back to the defaults, with the
    // monitoring install skipped honestly — it would target the default
    // interface name, which may not be the one installed.
    _options = run.options ?? const AdvancedOptions(enableMonitoring: false);
    _paths = paths;
    _launchedPaths = paths;
    _sshPassword = sshPassword ?? '';
    _newUser = null;
    _wantsHardening = false;
    _appKeyPair = null;
    _sshPublicKey = null;
    _recoveredManagement = null;
    _cancelled = false;
    // Restore the management identity the run deployed the app key to
    // (module 25) — but only when the matching local key pair still exists:
    // registering `sshKeyId` without it would leave every later operation
    // authenticating key-only against nothing (C1 class). `get`, never
    // `getOrCreate` — a fresh pair would not match the deployed key.
    final managed = run.managementUsername;
    if (managed != null) {
      final pair = await ref.read(sshKeyRepositoryProvider).get(server.id);
      if (pair != null) {
        _appKeyPair = pair;
        _recoveredManagement = managed;
      }
    }
    // The monitor install (post-success) uploads from the script bundle;
    // start() initializes these, a recovered flow must too. On failure the
    // monitoring is skipped rather than failing the recovery (audit M3 —
    // `_bundle` used to stay uninitialized and threw on every recovered
    // success).
    try {
      _resolver = await ref.read(effectiveScriptResolverProvider.future);
      _bundle = await _resolver.effectiveBundle();
    } on Object catch (error) {
      appLogger.w(
        'recovered-run bundle init failed: ${error.runtimeType}; '
        'skipping the monitoring install',
      );
      _options = _options.copyWith(enableMonitoring: false);
    }
    state = InstallRunning(run);
    // The resumed poll reads the root-owned state/exit files; a non-root
    // sudoer login needs sudo (password via stdin), matching the recovery
    // read. Null for a root login, or a key-auth login with no password
    // available (a known non-root key-auth recovery gap).
    final sudoPassword =
        server.username != 'root' && (sshPassword?.isNotEmpty ?? false)
        ? sshPassword
        : null;
    final pollState = await _pollToCompletion(
      client: client,
      run: run,
      paths: paths,
      sudoPassword: sudoPassword,
    );
    await _handlePollResult(run, pollState);
  }

  /// Cancels a running or pending installation.
  void cancel() {
    _cancelled = true;
    if (state is InstallNeedsConfirmation) {
      _pendingRun = null;
      state = const InstallIdle();
      return;
    }
    ref.read(runPollingControllerProvider.notifier).stop();
  }

  /// Resets the controller so a new installation can be started.
  ///
  /// Clears the transient SSH and new-user passwords held for the run, and
  /// drops the reference to the hardening key pair (the seed stays in the
  /// secure store, indexed by server id).
  void reset() {
    final leftover = _launchedPaths;
    final current = state;
    // Leaving the failure context: remove the residue best-effort (audit F5),
    // but ONLY when the run failed terminally — the poller observed the exit
    // file, so the detached installer is dead. Cancel and polling-timeout
    // also surface as InstallFailure while the installer may still be
    // running: wiping the run dir would kill it mid-flight and break the
    // §7.3 recovery contract (security review H1). Gating on the observed
    // exit also keeps connect/auth failures from spending a second auth
    // attempt against a fail2ban jail (M1). Every input is snapshotted into
    // the call before the transient credentials are wiped below.
    if (current is InstallFailure &&
        current.run?.status == RunStatus.failed &&
        leftover != null) {
      unawaited(
        cleanupRun(
          server: _server,
          paths: leftover,
          password: _passwordForResume(),
        ),
      );
    }
    _launchedPaths = null;
    _cancelled = false;
    _sshPassword = '';
    _newUser = null;
    _appKeyPair = null;
    _sshPublicKey = null;
    _recoveredManagement = null;
    _wantsHardening = false;
    state = const InstallIdle();
  }

  /// Fetches the full installer log from the server (best-effort, §11.2).
  Future<String> fetchRunLog() async {
    final client = ref.read(sshClientFactoryProvider)();
    try {
      await client.connect(
        await _paramsFor(_server, password: _passwordForResume()),
      );
      final result = await client.run(
        "cat '${_paths.logPath}' 2>/dev/null",
      );
      // The bundled modules never log secrets, but the log is produced by
      // scripts the user may edit and is then copied/shared off-device — run
      // it through the block-aware redaction (a PEM body must not survive
      // line-by-line, audit M3) and mask key-length base64 runs.
      final redacted = redactSecretLines(result.stdout.split('\n'));
      return redacted
          .map(
            (line) => line.replaceAll(
              _keyLikeBase64,
              '<redacted: key-like value>',
            ),
          )
          .join('\n');
    } on Object catch (error) {
      // Best-effort: log the failure type only — never the message, which
      // could carry transient transport details. Leaves a diagnostic trail
      // for QA without leaking secrets.
      appLogger.w('fetchRunLog failed: ${error.runtimeType}');
      return '';
    } finally {
      await client.close();
    }
  }

  /// Removes the run directory and state files from the server (§11.2).
  ///
  /// Returns whether the removal was verified. Success is signalled by a
  /// stdout marker, NOT the exit code: the stdin-less exec channel reports
  /// no exit code (-1) against OpenSSH >= 10 even when the command ran fine
  /// (same quirk as the teardown/hardening markers — audit F6).
  ///
  /// [server], [paths] and [password] default to the current run's fields;
  /// [reset] passes explicit snapshots so its fire-and-forget cleanup cannot
  /// race a subsequently started install (audit F5).
  Future<bool> cleanupRun({
    Server? server,
    RunPaths? paths,
    String? password,
  }) async {
    const marker = 'WG-CLN-OK';
    final target = server ?? _server;
    final runPaths = paths ?? _paths;
    final pwd = password ?? _passwordForResume();
    SshClient? client;
    try {
      // Inside the try: a disposed container must fail soft, not escape as
      // an unhandled zone error from the fire-and-forget path (review L2).
      client = ref.read(sshClientFactoryProvider)();
      await client.connect(await _paramsFor(target, password: pwd));
      // The state/exit/pid files are root-written; a sudoer login elevates
      // (audit F3). Their removal is best-effort (`;`): the marker — and so
      // the reported outcome — is tied to the run DIR, the only piece that
      // can hold secrets. A key-auth non-root login has no sudo password and
      // must still report success after removing it (review L5).
      final result = await _runMaybeSudo(
        client,
        "rm -f '${runPaths.statePath}' "
        "'${runPaths.exitPath}' '${runPaths.pidPath}' "
        "'${runPaths.logPath}' 2>/dev/null; "
        "rm -rf '${runPaths.runDir}' && printf '$marker\\n'",
        target.username != 'root' ? pwd : null,
      );
      return result.stdout.contains(marker);
    } on Object catch (error) {
      // Best-effort cleanup: log the failure type so a regression that hides
      // ERR-KEY-01 (and would leave the run directory on the server) is
      // visible in QA. Type only — never the message.
      appLogger.w('cleanupRun failed: ${error.runtimeType}');
      return false;
    } finally {
      await client?.close();
    }
  }

  Future<void> _proceedWithInstall(SshClient client, InstallRun run) async {
    // Last boundary before anything is created on the server (audit M4).
    if (_cancelled) {
      await client.close();
      state = const InstallFailure(error: _cancelledError);
      return;
    }
    state = const InstallPreparing();
    // When the SSH login is a non-root sudoer (root login disabled / unused),
    // elevate the run-dir creation, the detached launch and the state polling
    // with `sudo -S` (password via stdin). For a root login these stay null.
    final needsSudo = _server.username != 'root';
    final sudoPassword = needsSudo ? _sshPassword : null;
    // Persist the generated v2 identity and ULA before the first upload. A
    // confirmation retry or process recovery must reuse these exact values.
    await ref.read(runRepositoryProvider).save(run);
    try {
      final provisioner = DebianProvisioner(
        client: client,
        paths: _paths,
        bundle: _bundle,
      );
      // Phase 1 always keeps root SSH enabled; the anti-lockout sequence
      // disables it later from a verified second session (spec §10.2).
      await provisioner.start(
        sshPort: _server.sshPort,
        options: _options,
        newUser: _newUser,
        sshPublicKey: _sshPublicKey,
        sudoPassword: sudoPassword,
        loginUser: needsSudo ? _server.username : null,
        // _buildInitialRun always creates these v2 fields before this method
        // is reached. The provisioner requires them so an incomplete run can
        // never yield a config.env without the versioned network contract.
        installationId: run.installationId!,
        operationId: run.operationId!,
        ipv6UlaSubnet: run.ipv6UlaSubnet!,
      );
    } on ProvisioningLaunchUncertain catch (error) {
      await client.close();
      // The command may have launched the detached installer before its SSH
      // reply was lost. Keep the run recoverable instead of misclassifying it
      // as orphaned or deleting its remote state.
      await ref.read(runRepositoryProvider).save(run);
      ref.invalidate(incompleteRunsProvider);
      state = InstallFailure(
        error: AppException(mapSshError(error.cause)),
        run: run,
      );
      return;
    } on AppException catch (error) {
      await client.close();
      final failed = run.copyWith(
        status: RunStatus.orphaned,
        completedAt: DateTime.now(),
      );
      await ref.read(runRepositoryProvider).save(failed);
      state = InstallFailure(error: error, run: failed);
      return;
    } on Object catch (error) {
      await client.close();
      final failed = run.copyWith(
        status: RunStatus.orphaned,
        completedAt: DateTime.now(),
      );
      await ref.read(runRepositoryProvider).save(failed);
      state = InstallFailure(
        error: AppException(mapSshError(error)),
        run: failed,
      );
      return;
    }
    // A cancel that landed during the upload/launch: the detached installer
    // is already running, so the run stays persisted (recovery contract,
    // §7.3) and attached to the failure — only the polling is skipped.
    if (_cancelled) {
      await client.close();
      state = InstallFailure(error: _cancelledError, run: run);
      return;
    }
    state = InstallRunning(run);
    final pollState = await _pollToCompletion(
      client: client,
      run: run,
      paths: _paths,
      sudoPassword: sudoPassword,
    );
    await _handlePollResult(run, pollState);
  }

  InstallRun _buildInitialRun(
    Server server,
    RunPaths paths,
    ScriptBundle bundle,
    bool scriptWasModified,
  ) {
    return InstallRun(
      runId: paths.runId,
      serverId: server.id,
      status: RunStatus.running,
      steps: [
        for (final key in kRunStepKeys)
          InstallStep(key: key, status: StepStatus.pending, label: key),
      ],
      // The effective bundle hash covers exactly what is uploaded: equal to
      // the canonical bundled hash when no override exists, different when the
      // user has customized one or more scripts.
      scriptContentHash: bundle.bundleHash,
      scriptWasModified: scriptWasModified,
      startedAt: DateTime.now(),
      // Persisted so a recovered run finalizes with the interface/port/
      // subnet it was actually launched with (audit M3). Never secrets.
      options: _options,
      // The account module 25 deploys the app key to — mirrors the
      // ConfigEnvWriter NEW_USERNAME fallback. Lets a recovered run restore
      // the management identity at finalize.
      managementUsername: _newUser?.username ?? server.username,
      installationId: const Uuid().v4(),
      operationId: paths.runId,
      ipv6UlaSubnet: generateUlaSubnet(),
    );
  }

  /// Builds [SshConnectionParams] via [SshAuthResolver].
  ///
  /// When [server] carries a stored SSH key (hardening was applied)
  /// [password] is ignored and key-based auth is used. Otherwise the
  /// resolver falls back to [password], which must be non-empty in that
  /// case.
  Future<SshConnectionParams> _paramsFor(
    Server server, {
    String? password,
  }) {
    return ref
        .read(sshAuthResolverProvider)
        .resolve(server: server, password: password);
  }

  /// Returns the cached SSH password, or `null` when none is held — used by
  /// post-install operations so the resolver picks the stored key after
  /// `_sshPassword` was wiped at the end of [_finalizeSuccess].
  String? _passwordForResume() => _sshPassword.isEmpty ? null : _sshPassword;

  /// Runs [command] on [client], elevating with `sudo -S` (password via stdin)
  /// when [sudoPassword] is set — for reading root-owned files as a non-root
  /// login. Runs it plainly when null (root login).
  Future<SshCommandResult> _runMaybeSudo(
    SshClient client,
    String command,
    String? sudoPassword,
  ) {
    if (sudoPassword == null) {
      return client.run(command);
    }
    return client.run(
      "sudo -S -p '' -- sh -c ${shellSingleQuote(command)}",
      stdin: '$sudoPassword\n',
    );
  }

  Future<RunPollingState> _pollToCompletion({
    required SshClient client,
    required InstallRun run,
    required RunPaths paths,
    String? sudoPassword,
  }) async {
    // An active listener keeps the auto-dispose polling controller alive
    // until the loop terminates, even before the screen subscribes.
    final subscription = ref.listen(
      runPollingControllerProvider,
      (_, _) {},
    );
    try {
      await ref
          .read(runPollingControllerProvider.notifier)
          .start(
            client: client,
            run: run,
            paths: paths,
            sudoPassword: sudoPassword,
            reconnect: () async {
              final replacement = ref.read(sshClientFactoryProvider)();
              try {
                await replacement.connect(
                  await _paramsFor(_server, password: _passwordForResume()),
                );
                return replacement;
              } on Object {
                await replacement.close();
                rethrow;
              }
            },
          );
      return await ref.read(runPollingControllerProvider);
    } finally {
      subscription.close();
    }
  }

  Future<void> _handlePollResult(
    InstallRun run,
    RunPollingState pollState,
  ) async {
    // The poller has persisted the run's terminal status by now: refresh the
    // cached incomplete-runs list so the resume banner stops offering a run
    // that already finished (device test 2026-08-19). On a timeout the run
    // is still `running` in the repository and correctly stays listed.
    ref.invalidate(incompleteRunsProvider);
    final finalRun = pollState.run ?? run;
    if (_cancelled) {
      state = InstallFailure(error: _cancelledError, run: finalRun);
      return;
    }
    if (pollState.error != null) {
      await _rollbackFailedInstall();
      state = InstallFailure(
        error: pollState.error!,
        run: finalRun,
        failedStepKey: _failedStepKey(finalRun),
      );
      return;
    }
    if (finalRun.status != RunStatus.success) {
      state = InstallFailure(
        error: const AppException(ErrorCode.runStepFailed),
        run: finalRun,
        failedStepKey: _failedStepKey(finalRun),
      );
      return;
    }
    try {
      await _finalizeSuccess(finalRun);
    } on AppException catch (error) {
      state = InstallFailure(error: error, run: finalRun);
    }
  }

  /// Reverts a terminally failed fresh installation. A late module failure
  /// can happen after wg0, firewall rules and forwarding were already
  /// enabled; leaving those active would turn a reported failure into an
  /// unmanaged partial deployment. Keep the original run files for the
  /// failure screen's diagnostics; reset/cleanup removes them afterwards.
  Future<void> _rollbackFailedInstall() async {
    final client = ref.read(sshClientFactoryProvider)();
    try {
      await client.connect(
        await _paramsFor(_server, password: _passwordForResume()),
      );
      final outcome = await ref
          .read(servicesTeardownServiceProvider)
          .run(
            client: client,
            bundle: _bundle,
            interfaceName: _options.interfaceName,
            vpnSubnet: _options.vpnSubnet,
            sudoPassword: _server.username == 'root'
                ? null
                : _passwordForResume(),
            sweepInstallerDirs: false,
          );
      if (outcome is ServicesTeardownAborted) {
        appLogger.w('Failed-install rollback was not verified');
      }
    } on Object catch (error) {
      appLogger.w(
        'Failed-install rollback threw ${error.runtimeType}',
      );
    } finally {
      await client.close();
    }
  }

  Future<void> _finalizeSuccess(InstallRun run) async {
    // Read metadata before anti-lockout: disabling root SSH would block a
    // later connection when the server was added as `root`. The client
    // profile lives in the run directory (`99_finalize.sh`) — fetch and
    // persist it in the same session (best-effort, spec §8.2 RF-16).
    final metadata = await _readInstallationMetadata(run);
    if (metadata.rawProfile != null) {
      await _persistClientProfile(metadata.rawProfile!);
    }

    final portReachability = await _checkWireguardPort();

    final identity = ManagementIdentity.resolve(
      newUser: _newUser,
      loginUsername: _server.username,
      loginPassword: _sshPassword,
    );

    var rootSshDisabled = false;
    AppException? lockoutWarning;
    if (_wantsHardening) {
      state = InstallAntiLockout(run);
      final outcome = await ref
          .read(antiLockoutServiceProvider)
          .disableRootSsh(
            server: _server,
            identity: identity,
            paths: _paths,
            scriptBytes: await _resolver.bytesFor(kAntiLockoutScript),
          );
      if (outcome is AntiLockoutAborted) {
        lockoutWarning = outcome.error;
      } else {
        rootSshDisabled = true;
      }
    }

    var hardeningApplied = false;
    AppException? hardeningWarning;
    final keyPair = _appKeyPair;
    if (_wantsHardening && keyPair != null) {
      state = InstallHardening(run);
      try {
        final outcome = await ref
            .read(hardeningServiceProvider)
            .apply(
              server: _server,
              identity: identity,
              keyPair: keyPair,
              paths: _paths,
              scriptBytes: await _resolver.bytesFor(kDisablePasswordAuthScript),
            );
        if (outcome is HardeningAborted) {
          hardeningWarning = outcome.error;
        } else {
          hardeningApplied = true;
        }
      } on Object catch (error) {
        appLogger.e('Hardening flow threw: ${error.runtimeType}');
        hardeningWarning = AppException(
          ErrorCode.lockoutAborted,
          detail: 'hardening failed unexpectedly: ${error.runtimeType}',
        );
      }
    }

    // The app authenticates as the account that received the app SSH key —
    // see [resolveManagedUsername]. A recovered run restores it from the
    // persisted run record instead (M3): `_newUser` is gone, but module 25
    // deployed the key to that account and the pair was verified to still
    // exist locally in [attachRecovered].
    final loginUser =
        _recoveredManagement ??
        resolveManagedUsername(
          identity: identity,
          loginUsername: _server.username,
        );
    // Positive evidence that module 25 never ran (a user-edited bundle can
    // skip deploy_app_key and still succeed) blocks the key registration:
    // key-only auth against a missing authorized_key is the C1 failure
    // class. Absent step data (recovered runs whose state file is gone)
    // keeps the proven-by-success behavior.
    final deployStep = run.steps
        .where((s) => s.key == 'deploy_app_key')
        .firstOrNull;
    final deployDenied =
        deployStep != null && deployStep.status != StepStatus.done;
    final hasAppKey = _appKeyPair != null && !deployDenied;
    // With negative evidence AND a changed management account, a
    // pre-existing key claim is stale too: the old key belongs to the old
    // account (verify-pass LOW-5).
    final clearStaleKey = deployDenied && loginUser != _server.username;
    final updatedServer = _server.copyWith(
      username: loginUser,
      installation: metadata.installation.copyWith(
        hardeningApplied: hardeningApplied,
        rootSshDisabled: rootSshDisabled,
        portReachability: portReachability,
        portCheckedAt: portReachability == WireguardPortReachability.unknown
            ? null
            : DateTime.now(),
        publicEndpoint: _options.publicEndpoint ?? _server.host,
      ),
      sshKeyId: hasAppKey ? _server.id : _server.sshKeyId,
      clearSshKeyId: clearStaleKey,
      lastSeenAt: DateTime.now(),
      // Record the user-supplied keys deployed by `26_deploy_user_keys` so the
      // server detail screen can list and manage them.
      userAuthorizedKeys: _options.userAuthorizedKeys,
    );
    await ref.read(serverRepositoryProvider).save(updatedServer);
    ref.invalidate(serverListControllerProvider);

    // Sudo password for the post-install steps, which connect as `loginUser`:
    // the management user's password when we now log in as that user, otherwise
    // the original SSH login password (a non-root sudoer that was the login).
    // Null for a root login (no sudo needed).
    final newUser = _newUser;
    final postSudoPassword = loginUser == newUser?.username
        ? newUser?.password
        : (loginUser == 'root' ? null : _passwordForResume());

    // M15-T7: install the peer-monitoring agent (default ON). Failure is a
    // non-fatal warning — monitoring will simply be `notInstalled` in the UI.
    // Runs while the new-user password is still in memory so sudo works
    // when the server has a non-root login user.
    var monitoringInstalled = false;
    AppException? monitoringWarning;
    if (_options.enableMonitoring) {
      // On a recovered run the management user's password is unknown, so
      // sudo as that account is impossible: install the agent over the
      // resume login instead (root directly, or the sudoer login whose
      // password the resume prompt provided). The snapshot is still chowned
      // to [loginUser] via newUsername, matching the key-authenticated
      // polls that follow.
      final monitorTarget = _recoveredManagement != null
          ? _server
          : updatedServer;
      try {
        final outcome = await ref
            .read(monitoringInstallServiceProvider)
            .install(
              server: monitorTarget,
              bundle: _bundle,
              wgInterface: _options.interfaceName,
              sudoPassword: postSudoPassword,
              // The snapshot must be readable by whoever the app polls as —
              // the login user — not necessarily the freshly created user.
              newUsername: loginUser,
              // Fallback for a server without a registered app key (a
              // recovered run): still in memory here, wiped right below.
              password: _passwordForResume(),
            );
        if (outcome is MonitoringInstallAborted) {
          monitoringWarning = outcome.error;
        } else {
          monitoringInstalled = true;
        }
      } on Object catch (error) {
        // M15-T10 (security audit): type-only — see hardening branch above.
        appLogger.e('Monitoring install threw: ${error.runtimeType}');
        monitoringWarning = AppException(
          ErrorCode.scriptInvalid,
          detail: 'monitor install failed: ${error.runtimeType}',
        );
      }
    }

    final completedRun = run.copyWith(
      status: RunStatus.success,
      completedAt: DateTime.now(),
      network: metadata.installation.network,
    );
    await ref.read(runRepositoryProvider).save(completedRun);

    // No further SSH operations after this point — drop the transient
    // password (and the new-user password and key-pair reference) so they do
    // not linger in memory until the user taps Done (security review L3).
    // The seed bytes are still safely kept in the secure store under the
    // server id and can be re-read on demand.
    _sshPassword = '';
    _newUser = null;
    _appKeyPair = null;
    _sshPublicKey = null;
    state = InstallSuccess(
      run: completedRun,
      rootSshDisabled: rootSshDisabled,
      hardeningApplied: hardeningApplied,
      monitoringInstalled: monitoringInstalled,
      monitoringWarning: monitoringWarning,
      configBackupPath: metadata.backupPath,
      lockoutWarning: lockoutWarning,
      hardeningWarning: hardeningWarning,
    );
  }

  Future<WireguardPortReachability> _checkWireguardPort() async {
    final client = ref.read(sshClientFactoryProvider)();
    try {
      await client.connect(
        await _paramsFor(_server, password: _passwordForResume()),
      );
      return await const WireguardPortReachabilityService().check(
        client: client,
        endpoint: _options.publicEndpoint ?? _server.host,
        port: _options.wgPort,
        useSudo: _server.username != 'root',
        sudoPassword: _server.username == 'root' ? null : _passwordForResume(),
      );
    } on Object catch (error) {
      appLogger.w('WireGuard port probe failed: ${error.runtimeType}');
      return WireguardPortReachability.unknown;
    } finally {
      await client.close();
    }
  }

  Future<
    ({
      WireguardInstallation installation,
      String? backupPath,
      String? rawProfile,
    })
  >
  _readInstallationMetadata(InstallRun run) async {
    final iface = _options.interfaceName;
    var serverPublicKey = '';
    String? backupPath;
    String? rawProfile;
    NetworkConfiguration? network;
    final expectsV2 =
        run.installationId != null &&
        run.operationId != null &&
        run.ipv6UlaSubnet != null;
    // The server pubkey and the run-dir client.conf are root-owned (the
    // installer runs as root); when the login is a non-root sudoer we must
    // read them under sudo, otherwise `cat` returns nothing and the first
    // client profile is silently lost (no default peer).
    final sudoPassword = _server.username != 'root'
        ? _passwordForResume()
        : null;
    final client = ref.read(sshClientFactoryProvider)();
    try {
      await client.connect(
        await _paramsFor(_server, password: _passwordForResume()),
      );
      serverPublicKey = (await _runMaybeSudo(
        client,
        "cat '/etc/wireguard/${iface}_server_public.key' 2>/dev/null",
        sudoPassword,
      )).stdout.trim();
      final backup = (await _runMaybeSudo(
        client,
        'ls -1d /etc/wireguard/backups/*/ 2>/dev/null | tail -1',
        sudoPassword,
      )).stdout.trim();
      backupPath = backup.isEmpty ? null : backup;
      final profile = (await _runMaybeSudo(
        client,
        "cat '${_paths.clientConfigPath}' 2>/dev/null",
        sudoPassword,
      )).stdout;
      rawProfile = profile.isEmpty ? null : profile;
      if (expectsV2) {
        final result = (await _runMaybeSudo(
          client,
          "cat '${_paths.networkResultPath}' 2>/dev/null",
          sudoPassword,
        )).stdout;
        if (result.trim().isEmpty) {
          throw const AppException(
            ErrorCode.runStepFailed,
            detail: 'missing v2 network result',
          );
        }
        try {
          network = const NetworkResultParser().parse(
            result,
            expectedInstallationId: run.installationId!,
            expectedOperationId: run.operationId!,
            expectedIpv4Subnet: _options.vpnSubnet,
            expectedFallbackIpv6Subnet: run.ipv6UlaSubnet!,
          );
        } on FormatException {
          throw const AppException(
            ErrorCode.runStepFailed,
            detail: 'invalid v2 network result',
          );
        }
      }
      // The run directory holds `client.conf` (client private key + PSK) and
      // `config.env` (the optional new-user password). Both must not linger
      // on the server after the app has the data (spec §10.1) — wipe it
      // while we still have an authenticated session, together with the
      // root-written state/exit/pid files (audit F3), elevating for a
      // sudoer login.
      await _runMaybeSudo(
        client,
        "rm -rf '${_paths.runDir}' '${_paths.statePath}' "
        "'${_paths.exitPath}' '${_paths.pidPath}'",
        sudoPassword,
      );
    } on AppException {
      // A malformed/missing v2 result is a hard success gate, but the run
      // directory may still contain credentials. Remove only this run's
      // owned files before surfacing the failure.
      try {
        await _runMaybeSudo(
          client,
          "rm -rf '${_paths.runDir}' '${_paths.statePath}' "
          "'${_paths.exitPath}' '${_paths.pidPath}'",
          sudoPassword,
        );
      } on Object {
        appLogger.w('v2 result cleanup failed');
      }
      rethrow;
    } on Object catch (error) {
      if (expectsV2) {
        try {
          await _runMaybeSudo(
            client,
            "rm -rf '${_paths.runDir}' '${_paths.statePath}' "
            "'${_paths.exitPath}' '${_paths.pidPath}'",
            sudoPassword,
          );
        } on Object {
          appLogger.w('v2 result transport cleanup failed');
        }
        throw const AppException(
          ErrorCode.runStepFailed,
          detail: 'could not verify v2 network result',
        );
      }
      // Best-effort: the installation already succeeded. Log the failure
      // type so a regression that skips the runDir wipe (and leaves
      // `client.conf` on the server, §10.1) is visible in QA.
      appLogger.w('readInstallationMetadata failed: ${error.runtimeType}');
    } finally {
      await client.close();
    }
    return (
      installation: WireguardInstallation(
        interfaceName: iface,
        listenPort: _options.wgPort,
        vpnSubnet: _options.vpnSubnet,
        serverPublicKey: serverPublicKey,
        peers: const [],
        // Optimistic default — overridden by the caller once the hardening
        // outcome is known.
        hardeningApplied: false,
        installedAt: DateTime.now(),
        network: network,
      ),
      backupPath: backupPath,
      rawProfile: rawProfile,
    );
  }

  /// Validates the freshly-fetched client `.conf` and stores it as the
  /// first peer (multi-peer v1.1 storage layout): a Peer row in the
  /// encrypted Hive box plus the raw conf under `client_profile:<peerId>`
  /// in secure storage (spec §8.6 — the private key lives only in secure
  /// storage).
  Future<void> _persistClientProfile(String rawConf) async {
    final ClientProfile profile;
    try {
      profile = await const ClientProfileParser().parse(rawConf);
    } on Object {
      // Corrupt profile or any future parser failure: skip the save so the
      // success view does not advertise a profile we cannot reproduce. The
      // install itself succeeded — fail-closed on the persistence only.
      return;
    }
    final peerId = const Uuid().v4();
    final peer = Peer(
      id: peerId,
      serverId: _server.id,
      // The "First client" label is editable post-install via the rename
      // dialog; it is stored as a plain English string so the persistent
      // value is stable across device-language changes.
      label: 'First client',
      address: profile.address,
      ipv6Address: profile.ipv6Address,
      publicKey: profile.clientPublicKey,
      createdAt: DateTime.now(),
    );
    try {
      await ref
          .read(peerSecretRepositoryProvider)
          .save(peerId: peerId, rawConf: rawConf);
      await ref.read(peerRepositoryProvider).save(peer);
    } on Object {
      // Best-effort: keystore / Hive failures should not turn a successful
      // install into a failure. Compensate any partial write: if the Hive
      // row failed after the secret landed, the secret would be orphaned
      // and never referenced again (audit M-2). Best-effort delete.
      try {
        await ref.read(peerSecretRepositoryProvider).delete(peerId);
      } on Object {
        // Ignore: nothing meaningful we can do here.
      }
    }
  }

  /// The account the app authenticates as for every post-install SSH operation.
  ///
  /// Always the identity that received the app SSH key (the management
  /// [identity]'s username): for a root login that is the created management
  /// user, for a non-root sudoer it is the login user itself. It must never
  /// fall back to the original login when they differ — module 25 deploys the
  /// app key only to the management user, so recording any other account and
  /// then connecting key-only (`sshKeyId` set) would authenticate against an
  /// account with no key and lock the app out (audit C1).
  @visibleForTesting
  static String resolveManagedUsername({
    required ManagementIdentity identity,
    required String loginUsername,
  }) {
    return identity.createdByUs ? identity.username : loginUsername;
  }

  String? _failedStepKey(InstallRun run) {
    for (final step in run.steps) {
      if (step.status == StepStatus.error) {
        return step.key;
      }
    }
    return null;
  }
}

/// Controls the end-to-end installation flow.
final NotifierProvider<InstallController, InstallFlowState>
installControllerProvider =
    NotifierProvider<InstallController, InstallFlowState>(
      InstallController.new,
    );
