#!/usr/bin/env bash
# Run server-script tests with the Bash version required by the installer.
set -euo pipefail
cd "$(dirname "$0")/.."
if (( BASH_VERSINFO[0] < 4 )); then
  echo 'BATS requires Bash 4+. On macOS: brew install bash bats coreutils' >&2
  echo 'Then prepend Homebrew bin and coreutils/libexec/gnubin to PATH.' >&2
  exit 1
fi
if ! command -v bats >/dev/null 2>&1; then
  echo 'Install bats before running shell tests (see docs/testing.md).' >&2
  exit 1
fi
export BATS_SHELL="$BASH"
exec bats test/scripts/*.bats
