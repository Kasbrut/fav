#!/usr/bin/env bash
# Launch the Android emulator and run FAV on it.
#
# Run this in a DEDICATED terminal: the flutter dev hotkeys (`r` reload,
# `R` restart, `q` quit, `h` help) need stdin. Output is also mirrored to
# `.tmp/flutter-android.log` for troubleshooting without interrupting the dev loop.

set -euo pipefail

cd "$(dirname "$0")/.."
mkdir -p .tmp

SDK_ROOT="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
ADB="$SDK_ROOT/platform-tools/adb"
if [[ ! -x "$ADB" ]]; then
  # Fall back to whichever adb is on PATH.
  ADB="$(command -v adb || true)"
  if [[ -z "$ADB" ]]; then
    echo "❌ adb not found. Install Android SDK platform-tools."
    exit 1
  fi
fi

# Start the named emulator if no emulator-* device is connected yet.
if ! "$ADB" devices | grep -qE '^emulator-[0-9]+'; then
  echo "→ launching emulator fav_dev…"
  fvm flutter emulators --launch fav_dev >/dev/null 2>&1 &
  for _ in $(seq 1 60); do
    if "$ADB" devices | grep -qE '^emulator-[0-9]+'; then
      break
    fi
    sleep 2
  done
fi

DEVICE_ID="$("$ADB" devices | awk '/^emulator-/ { print $1; exit }')"
if [[ -z "${DEVICE_ID:-}" ]]; then
  echo "❌ No emulator detected after 2 min. Try \`fvm flutter emulators\`."
  exit 1
fi

# Wait for the Android OS to finish booting before flutter tries to install.
echo "→ waiting for $DEVICE_ID to finish booting…"
BOOTED=0
for _ in $(seq 1 60); do
  if [[ "$("$ADB" -s "$DEVICE_ID" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == "1" ]]; then
    BOOTED=1
    break
  fi
  sleep 2
done

if [[ "$BOOTED" -ne 1 ]]; then
  echo "Emulator $DEVICE_ID did not finish booting within 2 minutes." >&2
  exit 1
fi

echo "→ fvm flutter run -d $DEVICE_ID  (log mirrored to .tmp/flutter-android.log)"
echo "  hotkeys: r=reload  R=restart  q=quit  h=help"
echo
fvm flutter run -d "$DEVICE_ID" 2>&1 | tee .tmp/flutter-android.log
