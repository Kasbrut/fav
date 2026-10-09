// Pure parsers for the output of the system probe commands (spec §3.2, RF-07).
// Side-effect free and independent of SSH, so they are fully unit-testable.

/// Parses the `KEY=VALUE` lines of `/etc/os-release` into a map.
///
/// Surrounding single or double quotes are stripped from values.
Map<String, String> parseOsRelease(String content) {
  final result = <String, String>{};
  for (final rawLine in content.split('\n')) {
    final line = rawLine.trim();
    if (line.isEmpty || line.startsWith('#')) {
      continue;
    }
    final separator = line.indexOf('=');
    if (separator <= 0) {
      continue;
    }
    final key = line.substring(0, separator).trim();
    var value = line.substring(separator + 1).trim();
    if (value.length >= 2 &&
        ((value.startsWith('"') && value.endsWith('"')) ||
            (value.startsWith("'") && value.endsWith("'")))) {
      value = value.substring(1, value.length - 1);
    }
    result[key] = value;
  }
  return result;
}

/// Whether [osId] is a supported distribution (Debian or Ubuntu, spec §3.2).
bool isDistroSupported(String osId) {
  return osId == 'debian' || osId == 'ubuntu';
}

/// Whether [kernelRelease] (from `uname -r`) is recent enough for WireGuard.
///
/// WireGuard needs kernel 5.6 or newer (spec §3.2).
bool isKernelSupported(String kernelRelease) {
  final match = RegExp(r'^(\d+)\.(\d+)').firstMatch(kernelRelease);
  if (match == null) {
    return false;
  }
  final major = int.parse(match.group(1)!);
  final minor = int.parse(match.group(2)!);
  return major > 5 || (major == 5 && minor >= 6);
}

/// Parses total system memory in megabytes from `/proc/meminfo`.
///
/// Returns `0` when the `MemTotal` line is absent.
int parseMemTotalMb(String meminfo) {
  final match = RegExp(r'MemTotal:\s+(\d+)\s*kB').firstMatch(meminfo);
  if (match == null) {
    return 0;
  }
  return int.parse(match.group(1)!) ~/ 1024;
}
