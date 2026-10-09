#!/usr/bin/env bash
# Launch the iOS Simulator and run FAV on it.
#
# Run this in a DEDICATED terminal: the flutter dev hotkeys (`r` reload,
# `R` restart, `q` quit, `h` help) need stdin. Output is also mirrored to
# `.tmp/flutter-ios.log` for troubleshooting without interrupting the dev loop.

set -euo pipefail

cd "$(dirname "$0")/.."
mkdir -p .tmp

# Boot the simulator if nothing is up. `open -a Simulator` is idempotent.
if ! xcrun simctl list devices booted | grep -q 'Booted'; then
  echo "→ booting iOS Simulator…"
  open -a Simulator
  for _ in $(seq 1 30); do
    if xcrun simctl list devices booted | grep -q 'Booted'; then
      break
    fi
    sleep 1
  done
fi

# The first booted device — fine for the single-device dev workflow.
DEVICE_ID="$(xcrun simctl list devices booted | grep -Eo '[A-F0-9]{8}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{12}' | head -1 || true)"
if [[ -z "${DEVICE_ID:-}" ]]; then
  echo "❌ No booted iOS Simulator found. Open Xcode → Simulator first."
  exit 1
fi

echo "→ fvm flutter run -d $DEVICE_ID  (log mirrored to .tmp/flutter-ios.log)"
echo "  hotkeys: r=reload  R=restart  q=quit  h=help"
echo
fvm flutter run -d "$DEVICE_ID" 2>&1 | tee .tmp/flutter-ios.log
