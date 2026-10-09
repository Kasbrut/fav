#!/usr/bin/env bash
# Run FAV on this host's native desktop target (macOS, Linux or Windows).
#
# Run this in a DEDICATED terminal: the flutter dev hotkeys (`r` reload,
# `R` restart, `q` quit, `h` help) need stdin. Output is also mirrored to
# `.tmp/flutter-desktop.log` for troubleshooting without interrupting the dev loop.
#
# Note: on macOS the app needs to be signed with your own Apple Developer Team
# for production Keychain access (see docs/building.md).

set -euo pipefail

cd "$(dirname "$0")/.."
mkdir -p .tmp

case "$(uname -s)" in
  Darwin) TARGET=macos ;;
  Linux) TARGET=linux ;;
  MINGW* | MSYS* | CYGWIN*) TARGET=windows ;;
  *)
    echo "❌ Unsupported host '$(uname -s)': no desktop target to run." >&2
    exit 1
    ;;
esac

echo "→ fvm flutter run -d $TARGET  (log mirrored to .tmp/flutter-desktop.log)"
echo "  hotkeys: r=reload  R=restart  q=quit  h=help"
echo
fvm flutter run -d "$TARGET" 2>&1 | tee .tmp/flutter-desktop.log
