import 'package:fav/features/install/domain/advanced_options.dart';
import 'package:fav/features/install/domain/install_run.dart';
import 'package:fav/features/install/domain/install_step.dart';
import 'package:fav/features/servers/data/network_mappers.dart';

/// Serializes [run] to a storage map.
///
/// An [InstallRun] never holds secrets, so the whole object is safe to store.
Map<String, Object?> runToMap(InstallRun run) {
  return {
    'runId': run.runId,
    'serverId': run.serverId,
    'status': run.status.name,
    'steps': run.steps.map(_stepToMap).toList(),
    'scriptContentHash': run.scriptContentHash,
    'scriptWasModified': run.scriptWasModified,
    'startedAt': run.startedAt.toIso8601String(),
    'completedAt': run.completedAt?.toIso8601String(),
    'runType': run.runType.name,
    'options': run.options == null ? null : _optionsToMap(run.options!),
    'managementUsername': run.managementUsername,
    'network': run.network == null
        ? null
        : networkConfigurationToMap(run.network!),
    'installationId': run.installationId,
    'operationId': run.operationId,
    'ipv6UlaSubnet': run.ipv6UlaSubnet,
  };
}

/// Reconstructs an [InstallRun] from a storage map.
InstallRun runFromMap(Map<dynamic, dynamic> map) {
  final steps = map['steps'] as List<dynamic>;
  return InstallRun(
    runId: map['runId'] as String,
    serverId: map['serverId'] as String,
    status: _statusFromName(map['status'] as String),
    steps: steps
        .map((step) => _stepFromMap(step as Map<dynamic, dynamic>))
        .toList(),
    scriptContentHash: map['scriptContentHash'] as String?,
    scriptWasModified: map['scriptWasModified'] as bool,
    startedAt: DateTime.parse(map['startedAt'] as String),
    completedAt: _parseNullableDate(map['completedAt']),
    runType: _runTypeFromName(map['runType'] as String?),
    options: map['options'] == null
        ? null
        : _optionsFromMap(map['options'] as Map<dynamic, dynamic>),
    managementUsername: map['managementUsername'] as String?,
    network: map['network'] == null
        ? null
        : networkConfigurationFromMap(map['network']),
    installationId: map['installationId'] as String?,
    operationId: map['operationId'] as String?,
    ipv6UlaSubnet: map['ipv6UlaSubnet'] as String?,
  );
}

Map<String, Object?> _optionsToMap(AdvancedOptions options) {
  return {
    'wgPort': options.wgPort,
    'vpnSubnet': options.vpnSubnet,
    'dns': options.dns,
    'mtu': options.mtu,
    'interfaceName': options.interfaceName,
    'publicEndpoint': options.publicEndpoint,
    'enableHardening': options.enableHardening,
    'enableMonitoring': options.enableMonitoring,
    'backupExistingConfig': options.backupExistingConfig,
    'userAuthorizedKeys': options.userAuthorizedKeys,
    'delegatedIpv6Prefix': options.delegatedIpv6Prefix,
    'ipv6ProbeTarget': options.ipv6ProbeTarget,
  };
}

AdvancedOptions _optionsFromMap(Map<dynamic, dynamic> map) {
  return AdvancedOptions(
    wgPort: map['wgPort'] as int,
    vpnSubnet: map['vpnSubnet'] as String,
    dns: map['dns'] as String,
    mtu: map['mtu'] as int,
    interfaceName: map['interfaceName'] as String,
    publicEndpoint: map['publicEndpoint'] as String?,
    delegatedIpv6Prefix: map['delegatedIpv6Prefix'] as String?,
    ipv6ProbeTarget: map['ipv6ProbeTarget'] as String?,
    enableHardening: map['enableHardening'] as bool,
    enableMonitoring: map['enableMonitoring'] as bool,
    backupExistingConfig: map['backupExistingConfig'] as bool,
    userAuthorizedKeys: (map['userAuthorizedKeys'] as List<dynamic>)
        .cast<String>(),
  );
}

Map<String, Object?> _stepToMap(InstallStep step) {
  return {
    'key': step.key,
    'status': step.status.name,
    'label': step.label,
    'startedAt': step.startedAt?.toIso8601String(),
    'completedAt': step.completedAt?.toIso8601String(),
    'errorMessage': step.errorMessage,
  };
}

InstallStep _stepFromMap(Map<dynamic, dynamic> map) {
  return InstallStep(
    key: map['key'] as String,
    status: _stepStatusFromName(map['status'] as String),
    label: map['label'] as String,
    startedAt: _parseNullableDate(map['startedAt']),
    completedAt: _parseNullableDate(map['completedAt']),
    errorMessage: map['errorMessage'] as String?,
  );
}

DateTime? _parseNullableDate(Object? raw) {
  return raw == null ? null : DateTime.parse(raw as String);
}

RunStatus _statusFromName(String name) {
  return RunStatus.values.firstWhere(
    (value) => value.name == name,
    orElse: () => RunStatus.orphaned,
  );
}

RunType _runTypeFromName(String? name) {
  return RunType.values.firstWhere(
    (type) => type.name == name,
    orElse: () => RunType.install,
  );
}

StepStatus _stepStatusFromName(String name) {
  return StepStatus.values.firstWhere(
    (value) => value.name == name,
    orElse: () => StepStatus.pending,
  );
}
