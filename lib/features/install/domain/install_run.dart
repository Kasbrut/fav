import 'package:fav/core/utils/equality.dart';
import 'package:fav/features/install/domain/advanced_options.dart';
import 'package:fav/features/install/domain/install_step.dart';
import 'package:fav/features/servers/domain/wireguard_installation.dart';
import 'package:meta/meta.dart';

/// Whether a run installs WireGuard or tears it down.
///
/// Every run created today is [install]: services teardown now runs
/// synchronously via sudo (`ServicesTeardownService`) rather than as a
/// detached, state-file-polled run, so nothing constructs a [teardown] run.
/// The value is kept deliberately — the persisted run map already carries it,
/// and run recovery is intentionally run-type-agnostic, so a future detached
/// teardown could reuse the whole recover/poll machinery without a schema
/// change. See `run_recovery_service_test.dart` for the agnostic-recovery
/// coverage.
enum RunType {
  /// A standard installation run.
  install,

  /// A teardown run that removes WireGuard from the server. Reserved for a
  /// future detached teardown; no run of this type is created today.
  teardown,
}

/// Overall status of an installation run (spec §4.1).
enum RunStatus {
  /// Queued, not yet started.
  queued,

  /// Currently running on the server.
  running,

  /// Completed successfully.
  success,

  /// Completed with a failure.
  failed,

  /// Lost on the server, for example after a reboot or cleanup.
  orphaned,
}

/// A single execution of the installation script, identified by [runId].
@immutable
class InstallRun {
  /// Creates an [InstallRun].
  const InstallRun({
    required this.runId,
    required this.serverId,
    required this.status,
    required this.steps,
    required this.scriptWasModified,
    required this.startedAt,
    this.scriptContentHash,
    this.completedAt,
    this.runType = RunType.install,
    this.options,
    this.managementUsername,
    this.network,
    this.installationId,
    this.operationId,
    this.ipv6UlaSubnet,
  });

  /// App-generated UUID that keys the run state and log files on the server.
  final String runId;

  /// Identifier of the target server.
  final String serverId;

  /// Current overall status.
  final RunStatus status;

  /// Ordered list of installation steps.
  final List<InstallStep> steps;

  /// SHA-256 hash of the script actually uploaded; `null` before upload.
  final String? scriptContentHash;

  /// Whether the executed script was a user-modified variant.
  final bool scriptWasModified;

  /// When the run started.
  final DateTime startedAt;

  /// When the run finished; `null` while still running.
  final DateTime? completedAt;

  /// Whether this run installs or tears down.
  final RunType runType;

  /// The effective advanced options the run was launched with, so a
  /// recovered run can finalize with the interface/port/subnet it actually
  /// used instead of the defaults (audit M3). Never carries secrets. Null on
  /// records persisted before this field existed.
  final AdvancedOptions? options;

  /// The account module 25 deploys the app SSH key to (the created
  /// management user, or the login user when none is created). Lets a
  /// recovered run restore the management identity at finalize (M3);
  /// never a secret. Null on records persisted before this field existed.
  final String? managementUsername;

  /// Persisted effective network metadata.
  final NetworkConfiguration? network;

  /// Stable identity sent with a v2 provisioning request.
  final String? installationId;

  /// Idempotency identity of this provisioning operation.
  final String? operationId;

  /// Capture ULA generated once before upload and reused by recovery/retry.
  final String? ipv6UlaSubnet;

  /// Returns a copy of this run with the given fields replaced.
  InstallRun copyWith({
    String? runId,
    String? serverId,
    RunStatus? status,
    List<InstallStep>? steps,
    String? scriptContentHash,
    bool? scriptWasModified,
    DateTime? startedAt,
    DateTime? completedAt,
    RunType? runType,
    AdvancedOptions? options,
    String? managementUsername,
    NetworkConfiguration? network,
    String? installationId,
    String? operationId,
    String? ipv6UlaSubnet,
    bool clearNetwork = false,
  }) {
    return InstallRun(
      runId: runId ?? this.runId,
      serverId: serverId ?? this.serverId,
      status: status ?? this.status,
      steps: steps ?? this.steps,
      scriptContentHash: scriptContentHash ?? this.scriptContentHash,
      scriptWasModified: scriptWasModified ?? this.scriptWasModified,
      startedAt: startedAt ?? this.startedAt,
      completedAt: completedAt ?? this.completedAt,
      runType: runType ?? this.runType,
      options: options ?? this.options,
      managementUsername: managementUsername ?? this.managementUsername,
      network: clearNetwork ? null : (network ?? this.network),
      installationId: installationId ?? this.installationId,
      operationId: operationId ?? this.operationId,
      ipv6UlaSubnet: ipv6UlaSubnet ?? this.ipv6UlaSubnet,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is InstallRun &&
        other.runId == runId &&
        other.serverId == serverId &&
        other.status == status &&
        listEquals(other.steps, steps) &&
        other.scriptContentHash == scriptContentHash &&
        other.scriptWasModified == scriptWasModified &&
        other.startedAt == startedAt &&
        other.completedAt == completedAt &&
        other.runType == runType &&
        other.options == options &&
        other.managementUsername == managementUsername &&
        other.network == network &&
        other.installationId == installationId &&
        other.operationId == operationId &&
        other.ipv6UlaSubnet == ipv6UlaSubnet;
  }

  @override
  int get hashCode {
    return Object.hash(
      runId,
      serverId,
      status,
      Object.hashAll(steps),
      scriptContentHash,
      scriptWasModified,
      startedAt,
      completedAt,
      runType,
      options,
      managementUsername,
      network,
      installationId,
      operationId,
      ipv6UlaSubnet,
    );
  }
}
