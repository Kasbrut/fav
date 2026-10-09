#!/usr/bin/env bash
# Build the release artifacts of FAV for Android.
#
# Default output (the same set a release should ship): one APK per ABI
# (armeabi-v7a, arm64-v8a, x86_64 — ~10-12 MB each, the right pick when
# you know the device) PLUS the universal fat APK with every ABI bundled
# (works everywhere, ~3x the size). All land in
# build/app/outputs/flutter-apk/.
#
# Flags:
#   --bundle       Emit an Android App Bundle (AAB) instead of the APKs.
#                  Use this if you intend to upload to Google Play.
#   --install      After the build, `adb install` the universal APK on the
#                  first connected device (skipped with --bundle since AAB
#                  is not directly installable).
#
# Signing: configure android/key.properties or FAV_* signing environment
# variables (docs/building.md). FAV_ALLOW_DEBUG_SIGNING=true is an explicit
# opt-in for local smoke tests only; never distribute those artifacts.

set -euo pipefail

cd "$(dirname "$0")/.."

# Use FVM locally; CI uses the Flutter version pinned by the release workflow.
if command -v fvm >/dev/null 2>&1; then
  FLUTTER=(fvm flutter)
else
  FLUTTER=(flutter)
fi

ARTIFACT=apk         # apk | bundle
INSTALL=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bundle)  ARTIFACT=bundle ;;
    --install) INSTALL=1 ;;
    -h|--help)
      sed -n '2,20p' "$0"
      exit 0
      ;;
    *)
      echo "❌ Unknown flag: $1" >&2
      exit 1
      ;;
  esac
  shift
done

if [[ "$ARTIFACT" == "bundle" && "$INSTALL" -eq 1 ]]; then
  echo "❌ --install is incompatible with --bundle (AAB is not installable)." >&2
  exit 1
fi

echo "→ ${FLUTTER[*]} pub get"
"${FLUTTER[@]}" pub get --enforce-lockfile >/dev/null

if [[ "$ARTIFACT" == "bundle" ]]; then
  echo "→ ${FLUTTER[*]} build appbundle --release"
  "${FLUTTER[@]}" build appbundle --release
  OUT="build/app/outputs/bundle/release/app-release.aab"
  echo
  echo "✓ App bundle ready:"
  printf '  %s   (%s)\n' "$OUT" "$(du -h "$OUT" | cut -f1)"
  echo
  echo "Next steps:"
  echo "  • Upload to Google Play Console → Release → Production / Internal."
  echo "  • For sideloading from an AAB, use Google's bundletool."
  exit 0
fi

# ARTIFACT == apk from here on: per-ABI APKs first, then the universal fat
# one (the second build reuses most of the Gradle work). Their output names
# never collide, so both sets coexist in flutter-apk/.
echo "→ ${FLUTTER[*]} build apk --release --split-per-abi"
"${FLUTTER[@]}" build apk --release --split-per-abi
echo "→ ${FLUTTER[*]} build apk --release   (universal)"
"${FLUTTER[@]}" build apk --release

echo
echo "✓ APKs ready in build/app/outputs/flutter-apk/:"
ls -1 build/app/outputs/flutter-apk/*release*.apk 2>/dev/null | while read -r f; do
  printf '  %-60s %s\n' "$f" "$(du -h "$f" | cut -f1)"
done

# The universal APK also supports x86_64 emulators and older ARM devices.
INSTALL_APK="build/app/outputs/flutter-apk/app-release.apk"

echo
if [[ "$INSTALL" -eq 1 ]]; then
  SDK_ROOT="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
  ADB="$SDK_ROOT/platform-tools/adb"
  [[ -x "$ADB" ]] || ADB="$(command -v adb || true)"
  if [[ -z "$ADB" ]]; then
    echo "❌ adb not found; cannot install. APK is at $INSTALL_APK"
    exit 1
  fi
  DEVICE="$("$ADB" devices | awk 'NR>1 && $2=="device" {print $1; exit}')"
  if [[ -z "$DEVICE" ]]; then
    echo "❌ No connected device (emulator or USB) in 'device' state."
    echo "   Plug the phone with USB debugging on, or boot an emulator,"
    echo "   then re-run with --install."
    exit 1
  fi
  echo "→ adb -s $DEVICE install -r $INSTALL_APK"
  "$ADB" -s "$DEVICE" install -r "$INSTALL_APK"
else
  echo "To sideload:"
  echo "  adb install $INSTALL_APK"
  echo "  # or transfer the .apk to the device (AirDrop, email, Drive) and tap it."
fi
