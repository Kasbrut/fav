/// Privacy scrubber for log lines shared into a PUBLIC GitHub issue.
///
/// The SSH log lines carry `user@host:port` references and remote paths.
/// Those are not §10.1 secrets — passwords, keys and PSKs are redacted
/// upstream by the log buffer — but they identify the user's server, and
/// the extended-diagnostic allowlist deliberately excludes exactly these
/// (IP, hostname, username). The scrubber holds shared logs to that same
/// bar. Everything remains user-reviewable and editable before it leaves
/// the device.
library;

final RegExp _userAt = RegExp('[A-Za-z0-9._-]+@');
final RegExp _ipv4 = RegExp(r'\b(?:\d{1,3}\.){3}\d{1,3}\b');
final RegExp _domain = RegExp(r'\b(?:[A-Za-z0-9-]+\.)+([A-Za-z]{2,})\b');

/// Command traces carry `KEY='value'` env assignments; these keys hold
/// identifying values (the key names themselves are the triage signal).
final RegExp _identifyingEnv = RegExp(
  r"\b(NEW_USERNAME|USERNAME|PEER_LABEL|PUBLIC_ENDPOINT|DNS)='[^']*'",
);

/// The run-dir chown targets the login user (audit H2).
final RegExp _chownUser = RegExp("chown( -R)? '[^']*'");

/// Unpadded-or-padded base64 runs of host-key/WireGuard-key length: a
/// published SHA-256 host-key fingerprint is a Censys/Shodan lookup key
/// straight back to the masked IP (audit H1).
final RegExp _keyLikeBase64 = RegExp('[A-Za-z0-9+/]{43,}={0,2}');

/// Colon-grouped hex candidates for IPv6 (audit M1). Candidates that are
/// all digits without `::` (e.g. ISO timestamps) are kept by the guard in
/// [scrubLogLine].
final RegExp _ipv6Candidate = RegExp(
  r'\b[0-9A-Fa-f]{0,4}(?::[0-9A-Fa-f]{0,4}){2,7}(?:%[A-Za-z0-9]+)?',
);
final RegExp _hexLetter = RegExp('[A-Fa-f]');

/// Dotted tokens ending in these are file/unit names, not hostnames — the
/// log's own vocabulary (scripts, systemd units, state files) must survive
/// scrubbing or the report becomes unreadable. `.sh` shadows a real ccTLD;
/// a server hostname under it would stay unmasked — accepted, the preview
/// is editable.
const Set<String> _fileLikeSuffixes = {
  'sh',
  'dart',
  'conf',
  'json',
  'jsonl',
  'service',
  'timer',
  'env',
  'key',
  'pub',
  'log',
  'md',
  'yaml',
  'yml',
  'lock',
  'arb',
  'tsv',
  'logrotate',
  // Run files under /var/lib/wg-installer: masking `<run-id>.state` as
  // `<host>` confused real reports while protecting nothing — the same
  // UUID appears unmasked in the /opt run paths (device report 2026-09-08).
  'state',
  'exit',
  'pid',
};

/// Masks server-identifying values in a single log [line]:
/// usernames (`favops@` → `<user>@`), IPv4 addresses (port kept readable)
/// and hostnames.
String scrubLogLine(String line) {
  // Quoted env values first: their contents could otherwise be partially
  // rewritten by the narrower rules below.
  var out = line.replaceAllMapped(
    _identifyingEnv,
    (match) => "${match.group(1)}='<masked>'",
  );
  out = out.replaceAllMapped(
    _chownUser,
    (match) => "chown${match.group(1) ?? ''} '<user>'",
  );
  out = out.replaceAll(_userAt, '<user>@');
  out = out.replaceAll(_ipv4, '<ip>');
  out = out.replaceAllMapped(_ipv6Candidate, (match) {
    final candidate = match.group(0)!;
    // Digit-only colon groups without `::` are timestamps, not addresses.
    final looksLikeAddress =
        candidate.contains('::') || _hexLetter.hasMatch(candidate);
    return looksLikeAddress ? '<ip>' : candidate;
  });
  out = out.replaceAll(_keyLikeBase64, '<fingerprint>');
  return out.replaceAllMapped(_domain, (match) {
    final suffix = match.group(1)!.toLowerCase();
    return _fileLikeSuffixes.contains(suffix) ? match.group(0)! : '<host>';
  });
}

/// Scrubs every line and joins them for the editable preview.
String scrubLog(Iterable<String> lines) => lines.map(scrubLogLine).join('\n');
