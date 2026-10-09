import 'package:meta/meta.dart';
import 'package:uuid/uuid.dart';

/// Server-side file paths for a single installation run (spec §7.3).
///
/// Every state, log, pid and exit file on the server is keyed by [runId];
/// centralizing the layout here keeps the provisioner, the polling controller
/// and the recovery service consistent.
@immutable
class RunPaths {
  /// Creates a [RunPaths] for the given [runId].
  const RunPaths(this.runId);

  /// Creates a [RunPaths] with a freshly generated run identifier.
  factory RunPaths.generate() => RunPaths(const Uuid().v4());

  /// App-generated UUID identifying the run.
  final String runId;

  /// Root directory holding every run's working directory.
  static const String runRoot = '/opt/wg-installer';

  /// Directory holding the per-run state, pid and exit files.
  static const String stateDir = '/var/lib/wg-installer';

  /// Directory holding the per-run log file.
  static const String logDir = '/var/log/wg-installer';

  /// Working directory uploaded for this run (created mode 0700).
  String get runDir => '$runRoot/$runId';

  /// Path of the orchestrator script inside the run directory.
  String get scriptPath => '$runDir/install_wireguard.sh';

  /// Path of the shared bash library inside the run directory.
  String get commonLibPath => '$runDir/lib/common.sh';

  /// Path of the run parameters file inside the run directory (mode 0600).
  String get configPath => '$runDir/config.env';

  /// Path of the generated client profile inside the run directory.
  String get clientConfigPath => '$runDir/client.conf';

  /// Path of the authoritative v2 network result emitted by the server.
  String get networkResultPath => '$runDir/network-result.json';

  /// Path of a numbered installer module given its [fileName].
  String modulePath(String fileName) => '$runDir/modules/$fileName';

  /// Path of the JSON state file polled during the run.
  String get statePath => '$stateDir/$runId.state';

  /// Path of the file holding the installer process id.
  String get pidPath => '$stateDir/$runId.pid';

  /// Path of the file holding the final exit code.
  String get exitPath => '$stateDir/$runId.exit';

  /// Path of the full run log (stdout and stderr).
  String get logPath => '$logDir/$runId.log';

  @override
  bool operator ==(Object other) => other is RunPaths && other.runId == runId;

  @override
  int get hashCode => runId.hashCode;
}
