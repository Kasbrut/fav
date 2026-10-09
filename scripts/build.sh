#!/usr/bin/env bash
# Build release artifacts of FAV for one or more platforms.
#
# Usage:
#   ./scripts/build.sh [platform ...]
#
# Platforms: android ios macos linux windows
#   No arguments (or "all") builds every platform buildable on the current
#   host. Flutter cannot cross-compile desktop/mobile targets, so the host OS
#   constrains what can be built:
#     macOS   → macos, ios, android
#     Linux   → linux, android
#     Windows → windows, android
#   A platform that is requested explicitly but cannot be built on this host
#   is a hard error; one pulled in via "all" is reported and skipped.
#
# Android delegates to build-android.sh (per-ABI and universal APKs by default);
# call that script directly for its --bundle / --install flags. iOS is built
# unsigned (--no-codesign) for local verification.

set -euo pipefail

cd "$(dirname "$0")/.."

ALL_PLATFORMS=(android ios macos linux windows)

# Host OS → the platforms it can build.
case "$(uname -s)" in
  Darwin) HOST_BUILDABLE=(macos ios android) ;;
  Linux) HOST_BUILDABLE=(linux android) ;;
  MINGW* | MSYS* | CYGWIN*) HOST_BUILDABLE=(windows android) ;;
  *) HOST_BUILDABLE=() ;;
esac

contains() {
  local needle="$1"
  shift
  local item
  for item in "$@"; do [[ "$item" == "$needle" ]] && return 0; done
  return 1
}

# Parse arguments into the requested platform list.
EXPLICIT=0
REQUESTED=()
if [[ $# -eq 0 ]]; then
  REQUESTED=("${ALL_PLATFORMS[@]}")
else
  for arg in "$@"; do
    case "$arg" in
      all) REQUESTED=("${ALL_PLATFORMS[@]}") ;;
      android | ios | macos | linux | windows)
        REQUESTED+=("$arg")
        EXPLICIT=1
        ;;
      -h | --help)
        sed -n '2,19p' "$0"
        exit 0
        ;;
      *)
        echo "❌ Unknown platform: $arg (expected: ${ALL_PLATFORMS[*]} all)" >&2
        exit 1
        ;;
    esac
  done
fi

# De-duplicate while preserving order.
PLATFORMS=()
for p in "${REQUESTED[@]}"; do
  contains "$p" "${PLATFORMS[@]:-}" || PLATFORMS+=("$p")
done

if [[ "$EXPLICIT" -eq 1 ]]; then
  for p in "${PLATFORMS[@]}"; do
    if ! contains "$p" "${HOST_BUILDABLE[@]:-}"; then
      echo "Cannot build '$p' on $(uname -s)." >&2
      exit 1
    fi
  done
fi

echo "→ fvm flutter pub get"
fvm flutter pub get --enforce-lockfile >/dev/null

BUILT=()
SKIPPED=()

report_output() {
  case "$1" in
    android) ;; # build-android.sh already prints its artifact list.
    ios) ls -d build/ios/iphoneos/*.app 2>/dev/null ;;
    macos) ls -d build/macos/Build/Products/Release/*.app 2>/dev/null ;;
    linux) ls -d build/linux/*/release/bundle 2>/dev/null ;;
    windows) ls -d build/windows/*/runner/Release 2>/dev/null ;;
  esac
}

build_one() {
  local p="$1"
  if ! contains "$p" "${HOST_BUILDABLE[@]:-}"; then
    if [[ "$EXPLICIT" -eq 1 ]]; then
      echo "❌ Cannot build '$p' on $(uname -s): Flutter has no cross-compiler for it." >&2
      exit 1
    fi
    echo "⏭  skipping $p (not buildable on $(uname -s))"
    SKIPPED+=("$p")
    return
  fi
  echo
  echo "═══ Building $p ═══"
  case "$p" in
    android) ./scripts/build-android.sh ;;
    ios) fvm flutter build ios --release --no-codesign ;;
    macos) fvm flutter build macos --release ;;
    linux) fvm flutter build linux --release ;;
    windows) fvm flutter build windows --release ;;
  esac
  BUILT+=("$p")
}

for p in "${PLATFORMS[@]}"; do build_one "$p"; done

echo
echo "✓ Build summary"
if [[ ${#BUILT[@]} -gt 0 ]]; then
  for p in "${BUILT[@]}"; do
    out="$(report_output "$p")"
    printf '  %-8s %s\n' "$p" "${out:-(see output above)}"
  done
else
  echo "  (nothing built)"
fi
if [[ ${#SKIPPED[@]} -gt 0 ]]; then
  echo "  skipped on this host: ${SKIPPED[*]}"
fi
