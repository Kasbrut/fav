# Shared setup for the WireGuard installer BATS suite.
# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154,SC2329  # consumed by the .bats test files.

# Absolute path to the bundled installer scripts under test.
SCRIPTS_DIR="$(cd "${BATS_TEST_DIRNAME}/../../lib/assets/scripts" && pwd)"

# Path to the generic system-command mock.
MOCK="${BATS_TEST_DIRNAME}/mocks/mock"

# System commands replaced by the mock during tests.
MOCK_COMMANDS=(
  apt-get useradd usermod chpasswd passwd id sshd systemctl
  wg sysctl iptables ip6tables ip ss netfilter-persistent uname
  getent chown flock
  apparmor_parser
)

# install_mocks <bin-dir>: symlink every mocked command into <bin-dir> and
# prepend it to PATH so the installer scripts call the mock instead.
install_mocks() {
  local bindir=$1 name
  mkdir -p "$bindir"
  for name in "${MOCK_COMMANDS[@]}"; do
    ln -sf "$MOCK" "$bindir/$name"
  done
  PATH="$bindir:$PATH"
}

# run_module <module-relpath> <run-fn>: run one installer module the way the
# orchestrator does — set -euo pipefail, common.sh and the module sourced —
# capturing status and output through BATS `run`.
run_module() {
  run bash -euo pipefail -c '
    source "$1"
    source "$2"
    "$3"
  ' _ "$SCRIPTS_DIR/lib/common.sh" "$SCRIPTS_DIR/$1" "$2"
}

# mock_called <command>: succeed if <command> was invoked at least once.
mock_called() {
  grep -q "^$1 " "$MOCK_LOG"
}
