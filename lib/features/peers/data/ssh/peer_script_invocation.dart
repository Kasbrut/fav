import 'dart:typed_data';

import 'package:fav/core/errors/app_exception.dart';
import 'package:fav/features/install/domain/ssh_client.dart';
import 'package:uuid/uuid.dart';

/// Marker echoed by [stagePeerScript]'s staging command. Its presence in
/// stdout — not the exit code — signals the private staging dir was created:
/// the command carries no stdin, so dartssh2 runs it over the plain exec
/// channel, which reports no exit code (-1) on OpenSSH >= 10 even on success.
const String peerStagedMarker = 'WG-PEER-STAGED';

/// Returns true when [stderr] is sudo's own password rejection — the script
/// never ran, so the failure is an authentication problem, not an apply
/// failure (audit F9).
///
/// With `sudo -S` fed a single wrong password, sudo prints
/// `Sorry, try again.`, hits EOF on the retry prompt
/// (`sudo: no password was supplied`) and summarises with
/// `sudo: N incorrect password attempt(s)`.
bool isSudoPasswordRejection(String stderr) {
  return stderr.contains('Sorry, try again.') ||
      stderr.contains('incorrect password attempt') ||
      stderr.contains('sudo: no password was supplied');
}

/// Shell-quotes [value] for inclusion in a single-quoted POSIX shell context.
///
/// Encloses [value] in single quotes and doubles up any embedded single
/// quote — the standard `'foo'\''bar'` trick — so the result is safe to
/// concatenate into a command string regardless of [value]'s contents.
String shellQuote(String value) {
  return "'${value.replaceAll("'", r"'\''")}'";
}

/// Builds the SSH command line that runs [remotePath] with [env] set, under
/// `sudo -S` (so it works both for a root login — sudo is a no-op — and for
/// a post-hardening non-root sudo user).
///
/// `sudo -p ''` suppresses sudo's password prompt text, so the caller can
/// stream the password via stdin without polluting stdout/stderr.
String buildSudoEnvCommand({
  required Map<String, String> env,
  required String remotePath,
}) {
  final parts = <String>['sudo', '-S', '-p', "''", '--', 'env'];
  // Sort keys so command strings are stable in tests.
  final keys = env.keys.toList()..sort();
  for (final key in keys) {
    parts.add('$key=${shellQuote(env[key]!)}');
  }
  parts
    ..add('bash')
    ..add(shellQuote(remotePath));
  return parts.join(' ');
}

/// A staged peer script: the private directory holding it and the script's
/// full remote path.
typedef StagedPeerScript = ({String dir, String path});

/// Creates a private, per-invocation 0700 staging directory under `/tmp` and
/// uploads [bytes] into it as [scriptName], returning the directory and the
/// script's full path.
///
/// The directory name is a random uuid, so it is not derivable from the
/// (public) script bytes: a local unprivileged user cannot pre-create the
/// script file and swap its contents between the upload and the subsequent
/// `sudo bash` run (audit H1 — the old bundle-hash `/tmp` path was identical
/// on every device). `mkdir -m 700` makes the directory unreadable/unwritable
/// to other users, and the preceding `rm -rf` clears any stale collision.
///
/// [dir] is injectable for deterministic tests. Throws [AppException]
/// ([ErrorCode.peerApplyFailed]) if the directory cannot be created.
Future<StagedPeerScript> stagePeerScript({
  required SshClient ssh,
  required String scriptName,
  required Uint8List bytes,
  String? dir,
}) async {
  final stagingDir = dir ?? '/tmp/wg-peer-${const Uuid().v4()}';
  final staged = await ssh.run(
    "rm -rf '$stagingDir' && mkdir -m 700 '$stagingDir' && "
    "printf '$peerStagedMarker\\n'",
  );
  if (!staged.stdout.contains(peerStagedMarker)) {
    throw const AppException(
      ErrorCode.peerApplyFailed,
      detail: 'failed to create the peer staging directory',
    );
  }
  final path = '$stagingDir/$scriptName';
  await ssh.uploadBytes(remotePath: path, data: bytes);
  return (dir: stagingDir, path: path);
}
