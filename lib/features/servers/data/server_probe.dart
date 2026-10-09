import 'package:fav/core/errors/app_exception.dart';
import 'package:fav/features/install/domain/ssh_client.dart';
import 'package:fav/features/servers/data/probe_parsers.dart';
import 'package:fav/features/servers/domain/server_metadata.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Collects system metadata from a server over an established SSH connection.
class ServerProbe {
  /// Creates a [ServerProbe].
  const ServerProbe();

  /// Probes the already-connected [client] and returns its [ServerMetadata].
  ///
  /// Throws an `AppException` with `ERR-SYS-01` for an unsupported
  /// distribution, or `ERR-SYS-02` for a kernel too old for WireGuard.
  Future<ServerMetadata> probe(SshClient client) async {
    final osRelease = parseOsRelease(
      await _stdout(client, 'cat /etc/os-release'),
    );
    final osId = (osRelease['ID'] ?? '').toLowerCase();
    if (!isDistroSupported(osId)) {
      throw const AppException(ErrorCode.sysUnsupportedDistro);
    }

    final kernel = (await _stdout(client, 'uname -r')).trim();
    if (!isKernelSupported(kernel)) {
      throw const AppException(ErrorCode.sysKernelTooOld);
    }

    final architecture = (await _stdout(client, 'uname -m')).trim();
    final hostname = (await _stdout(client, 'hostname')).trim();
    final meminfo = await _stdout(client, 'cat /proc/meminfo');
    final cpuText = (await _stdout(client, 'nproc')).trim();
    final interfaces = (await _stdout(
      client,
      'ls /sys/class/net',
    )).split(RegExp(r'\s+')).where((name) => name.isNotEmpty).toList();

    return ServerMetadata(
      osId: osId,
      osVersion: osRelease['VERSION_ID'] ?? '',
      prettyName: osRelease['PRETTY_NAME'] ?? '',
      kernelVersion: kernel,
      architecture: architecture,
      hostname: hostname,
      totalMemoryMb: parseMemTotalMb(meminfo),
      cpuCount: int.tryParse(cpuText) ?? 1,
      publicIp: await _probePublicIp(client),
      networkInterfaces: interfaces,
      probedAt: DateTime.now(),
    );
  }

  /// Resolves the public IP server-side, falling back to the primary
  /// interface address when no Internet echo service is reachable.
  Future<String> _probePublicIp(SshClient client) async {
    final viaEcho = (await _stdout(
      client,
      'curl -s --max-time 5 https://api.ipify.org',
    )).trim();
    if (viaEcho.isNotEmpty) {
      return viaEcho;
    }
    final addresses = (await _stdout(
      client,
      'hostname -I',
    )).split(RegExp(r'\s+')).where((token) => token.isNotEmpty);
    return addresses.isEmpty ? '' : addresses.first;
  }

  Future<String> _stdout(SshClient client, String command) async {
    final result = await client.run(command);
    return result.stdout;
  }
}

/// Provides the [ServerProbe].
final Provider<ServerProbe> serverProbeProvider = Provider<ServerProbe>(
  (ref) => const ServerProbe(),
);
