import 'package:fav/core/utils/equality.dart';
import 'package:meta/meta.dart';

/// System metadata collected from a server during the probe (spec RF-07).
@immutable
class ServerMetadata {
  /// Creates a [ServerMetadata].
  const ServerMetadata({
    required this.osId,
    required this.osVersion,
    required this.prettyName,
    required this.kernelVersion,
    required this.architecture,
    required this.hostname,
    required this.totalMemoryMb,
    required this.cpuCount,
    required this.publicIp,
    required this.networkInterfaces,
    required this.probedAt,
  });

  /// OS identifier (for example `debian`, `ubuntu`).
  final String osId;

  /// OS version string (for example `12 (bookworm)`).
  final String osVersion;

  /// Full OS name (for example `Debian GNU/Linux 12 (bookworm)`).
  final String prettyName;

  /// Kernel version (for example `6.1.0-13-amd64`).
  final String kernelVersion;

  /// CPU architecture (for example `x86_64`).
  final String architecture;

  /// Server hostname.
  final String hostname;

  /// Total system memory in megabytes.
  final int totalMemoryMb;

  /// Number of CPUs.
  final int cpuCount;

  /// Public IP address as determined by the server.
  final String publicIp;

  /// Names of the server network interfaces.
  final List<String> networkInterfaces;

  /// When the probe was performed.
  final DateTime probedAt;

  /// Returns a copy of this metadata with the given fields replaced.
  ServerMetadata copyWith({
    String? osId,
    String? osVersion,
    String? prettyName,
    String? kernelVersion,
    String? architecture,
    String? hostname,
    int? totalMemoryMb,
    int? cpuCount,
    String? publicIp,
    List<String>? networkInterfaces,
    DateTime? probedAt,
  }) {
    return ServerMetadata(
      osId: osId ?? this.osId,
      osVersion: osVersion ?? this.osVersion,
      prettyName: prettyName ?? this.prettyName,
      kernelVersion: kernelVersion ?? this.kernelVersion,
      architecture: architecture ?? this.architecture,
      hostname: hostname ?? this.hostname,
      totalMemoryMb: totalMemoryMb ?? this.totalMemoryMb,
      cpuCount: cpuCount ?? this.cpuCount,
      publicIp: publicIp ?? this.publicIp,
      networkInterfaces: networkInterfaces ?? this.networkInterfaces,
      probedAt: probedAt ?? this.probedAt,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ServerMetadata &&
        other.osId == osId &&
        other.osVersion == osVersion &&
        other.prettyName == prettyName &&
        other.kernelVersion == kernelVersion &&
        other.architecture == architecture &&
        other.hostname == hostname &&
        other.totalMemoryMb == totalMemoryMb &&
        other.cpuCount == cpuCount &&
        other.publicIp == publicIp &&
        listEquals(other.networkInterfaces, networkInterfaces) &&
        other.probedAt == probedAt;
  }

  @override
  int get hashCode {
    return Object.hash(
      osId,
      osVersion,
      prettyName,
      kernelVersion,
      architecture,
      hostname,
      totalMemoryMb,
      cpuCount,
      publicIp,
      Object.hashAll(networkInterfaces),
      probedAt,
    );
  }
}
