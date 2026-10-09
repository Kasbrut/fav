/// Single-quotes [value] for safe inclusion in a `sh -c` / `bash -c`
/// argument: the only character that can escape a single-quoted POSIX
/// string is the quote itself, rewritten as `'\''`.
///
/// Shared by every remote-command builder (provisioner, pollers, teardown,
/// install controller) — the copies used to drift (deep-audit low nit).
String shellSingleQuote(String value) => "'${value.replaceAll("'", r"'\''")}'";
