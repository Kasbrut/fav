import 'package:fav/core/errors/app_exception.dart';
import 'package:fav/core/utils/app_logger.dart';
import 'package:fav/features/install/application/ssh_auth_resolver.dart';
import 'package:fav/features/install/data/scripts/asset_script_repository.dart';
import 'package:fav/features/install/data/ssh/dart_ssh_client.dart';
import 'package:fav/features/install/domain/script_source.dart';
import 'package:fav/features/install/domain/ssh_client.dart';
import 'package:fav/features/servers/domain/server.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';
import 'package:meta/meta.dart';

/// Marker printed by `install_monitor.sh` on success.
const String _monitorInstallOkMarker = 'wg-monitor install complete';

/// Outcome of the monitoring-install sequence (M15-T7).
@immutable
sealed class MonitoringInstallOutcome {
  /// Const base constructor.
  const MonitoringInstallOutcome();
}

/// Agent installed and timer enabled.
class MonitoringInstallApplied extends MonitoringInstallOutcome {
  /// Creates a [MonitoringInstallApplied].
  const MonitoringInstallApplied();
}

/// Agent install aborted — non-fatal: monitoring will be unavailable.
class MonitoringInstallAborted extends MonitoringInstallOutcome {
  /// Creates a [MonitoringInstallAborted].
  const MonitoringInstallAborted(this.error);

  /// The failure to surface as a warning on the success screen.
  final AppException error;
}

/// Uploads the monitoring bundle to a fresh staging directory on the server
/// and runs `install_monitor.sh` (M15-T7). Designed as a non-blocking step:
/// any failure is wrapped in [MonitoringInstallAborted] so it can be shown
/// as a warning without failing the install as a whole.
class MonitoringInstallService {
  /// Creates a [MonitoringInstallService].
  MonitoringInstallService({
    required this._sshClientFactory,
    required this._authResolver,
    Logger? logger,
  }) : _logger = logger ?? appLogger;

  final SshClient Function() _sshClientFactory;
  final SshAuthResolver _authResolver;
  final Logger _logger;

  /// Installs the monitoring agent on [server], optionally elevating with
  /// [sudoPassword] when the login user is not root.
  ///
  /// [bundle] is the integrity-verified script bundle: the service picks
  /// the monitor assets from it. [newUsername] is the login user that
  /// needs read access to the snapshot/events files (defaults to root).
  /// [password] is the transient login password the resolver falls back to
  /// when the server has no registered app key — a recovered run finalizes
  /// without one (M3 residual), and resolving key-less and password-less
  /// silently aborted the whole install (live device test 2026-08-19).
  Future<MonitoringInstallOutcome> install({
    required Server server,
    required ScriptBundle bundle,
    required String wgInterface,
    String? sudoPassword,
    String? newUsername,
    String? password,
  }) async {
    final stagingDir = '/tmp/wg-monitor-${server.id}';
    final client = _sshClientFactory();
    try {
      _logger.i('Monitor install: connecting to ${server.host}');
      await client.connect(
        await _authResolver.resolve(server: server, password: password),
      );

      _logger.i('Monitor install: staging assets in $stagingDir');
      await client.run("rm -rf '$stagingDir' && mkdir -p '$stagingDir/lib'");

      for (final relPath in kMonitorBundleAssets) {
        final asset = bundle.assets.firstWhere(
          (entry) => entry.relativePath == relPath,
          orElse: () => throw const AppException(
            ErrorCode.scriptInvalid,
            detail: 'monitor bundle is missing one of the required assets',
          ),
        );
        await client.uploadBytes(
          remotePath: '$stagingDir/${asset.relativePath}',
          data: asset.bytes,
        );
      }
      await client.run(
        "chmod +x '$stagingDir/$kMonitorInstallScript' "
        "'$stagingDir/$kMonitorAgentScript'",
      );

      final needsSudo = server.username != 'root';
      final envPrefix = StringBuffer()
        ..write("NEW_USERNAME='${newUsername ?? server.username}' ")
        ..write("WG_INTERFACE='$wgInterface' ");
      final invocation =
          '$envPrefix'
          "bash '$stagingDir/$kMonitorInstallScript'";

      _logger.i(
        'Monitor install: running install_monitor.sh '
        '(${needsSudo ? "sudo" : "direct"})',
      );
      final SshCommandResult result;
      if (needsSudo) {
        if (sudoPassword == null || sudoPassword.isEmpty) {
          return const MonitoringInstallAborted(
            AppException(
              ErrorCode.authNoSudo,
              detail: 'sudo password not available for monitoring install',
            ),
          );
        }
        result = await client.run(
          "sudo -S -p '' -- env $invocation",
          stdin: '$sudoPassword\n',
        );
      } else {
        result = await client.run(invocation);
      }
      _logger.i('Monitor install: exit ${result.exitCode}');
      // Best-effort staging dir cleanup.
      await client.run("rm -rf '$stagingDir'");
      if (!result.isSuccess ||
          !result.stdout.contains(_monitorInstallOkMarker)) {
        return const MonitoringInstallAborted(
          AppException(
            ErrorCode.scriptInvalid,
            detail: 'install_monitor.sh failed',
          ),
        );
      }
      return const MonitoringInstallApplied();
    } on HostKeyUnknownException {
      _logger.w('Monitor install: host key mismatch on a pinned server');
      await client.close();
      return const MonitoringInstallAborted(
        AppException(ErrorCode.hostKeyMismatch),
      );
    } on AppException catch (error) {
      _logger.w('Monitor install: aborted with ${error.code.id}');
      await client.close();
      return MonitoringInstallAborted(error);
    } on Object catch (error) {
      // M15-T10 (security audit): never log the raw error/stack — remote
      // command stderr can land here and may carry user-supplied content.
      _logger.w('Monitor install: unexpected failure ${error.runtimeType}');
      return MonitoringInstallAborted(
        AppException(
          ErrorCode.scriptInvalid,
          detail: 'monitor install threw ${error.runtimeType}',
        ),
      );
    } finally {
      await client.close();
    }
  }
}

/// Provides the monitoring-install service.
final Provider<MonitoringInstallService> monitoringInstallServiceProvider =
    Provider<MonitoringInstallService>(
      (ref) => MonitoringInstallService(
        sshClientFactory: ref.watch(sshClientFactoryProvider),
        authResolver: ref.watch(sshAuthResolverProvider),
      ),
    );
