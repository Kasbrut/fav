import 'package:fav/features/install/domain/ssh_client.dart';

/// Server-side snippet that removes a single `authorized_keys` line. The line
/// to remove is read from stdin (`$(cat)`), so it is never interpolated into
/// the command and needs no shell escaping. No-op when the file is absent.
const String _removeSnippet =
    r'cd "$HOME" || exit 1; f=.ssh/authorized_keys; '
    r'[ -f "$f" ] || exit 0; '
    r'key="$(cat)"; tmp="$(mktemp)"; '
    r'grep -vxF -- "$key" "$f" > "$tmp" || true; '
    r'cat "$tmp" > "$f"; rm -f "$tmp"; chmod 600 "$f"';

/// Removes [publicKeyLine] (FAV's deployed app key) from the connected user's
/// `~/.ssh/authorized_keys`. The connected user owns the file, so no sudo is
/// needed. The line travels via stdin. Throws when the remote command fails.
Future<void> removeAppKeyFromAuthorizedKeys({
  required SshClient client,
  required String publicKeyLine,
}) async {
  final result = await client.run(_removeSnippet, stdin: publicKeyLine);
  if (!result.isSuccess) {
    throw StateError(
      'app-key removal failed (exit ${result.exitCode}): '
      '${result.stderr.trim()}',
    );
  }
}
