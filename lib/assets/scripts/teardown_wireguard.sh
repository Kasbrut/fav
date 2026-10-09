#!/usr/bin/env bash
# Services teardown orchestrator. Mirror of install_wireguard.sh in reverse:
# removes what FAV installed (WireGuard service/config, monitor agent, NAT
# rule, IP forwarding, fail2ban jail) and never touches OS packages or the
# created user. Runs synchronously over the app's SSH connection (staged in
# /tmp, elevated via sudo); it still writes a state/log file for diagnostics.
#
# Usage: teardown_wireguard.sh <run-dir>
set -euo pipefail
IFS=$'\n\t'
shopt -s nullglob

# Restrict files created during the run (state, log) to owner and group.
umask 027

RUN_DIR="${1:?run dir is required}"
RUN_ID="$(basename "$RUN_DIR")"
chmod 700 "$RUN_DIR"

STATE_DIR="${WG_STATE_DIR:-/var/lib/wg-installer}"
LOG_DIR="${WG_LOG_DIR:-/var/log/wg-installer}"
STATE_FILE="$STATE_DIR/$RUN_ID.state"
EXIT_FILE="$STATE_DIR/$RUN_ID.exit"
export RUN_ID STATE_DIR LOG_DIR STATE_FILE EXIT_FILE
mkdir -p "$STATE_DIR" "$LOG_DIR"

# shellcheck source=lib/common.sh disable=SC1091
source "$RUN_DIR/lib/common.sh"

# Teardown step keys (override the installer's STEP_KEYS from common.sh).
STEP_KEYS=(
  stop_service
  remove_monitor
  remove_firewall
  remove_forwarding
  remove_config
  remove_fail2ban_jail
)

if [[ -f "$RUN_DIR/config.env" ]]; then
  chmod 600 "$RUN_DIR/config.env"
  # shellcheck disable=SC1091
  source "$RUN_DIR/config.env"
  rm -f "$RUN_DIR/config.env"
fi

# Defense-in-depth: INTERFACE_NAME is interpolated into `rm -f` paths by the
# teardown modules, so reject a malformed value even though the app validated
# it at install time (audit M-script-validate, teardown parity).
if [[ -n ${INTERFACE_NAME:-} &&
  ! ${INTERFACE_NAME} =~ ^[a-z_][a-z0-9_-]{0,14}$ ]]; then
  printf 'INTERFACE_NAME is not a valid interface name; aborting\n' >&2
  exit 1
fi

trap on_installer_exit EXIT
state_init
log "WireGuard teardown started (run ${RUN_ID})"

exec 9>"$STATE_DIR/.wg-installer.lock"
flock 9
iface_lock=${INTERFACE_NAME:-wg0}
exec 8>"$STATE_DIR/.wg-installer-${iface_lock}.lock"
flock 8

for module in "$RUN_DIR"/teardown/modules/[0-9][0-9]_*.sh; do
  name="$(basename "$module" .sh)"
  name="${name#[0-9][0-9]_}"
  set_step "$name" "running"
  log "Step ${name} started"
  # shellcheck disable=SC1090
  source "$module"
  "run_${name}"
  set_step "$name" "done"
  log "Step ${name} done"
done

log "WireGuard teardown finished (run ${RUN_ID})"

# Success marker on stdout (mirrors install/reopen/hardening). `set -e` aborts
# the run before this line on any step failure, so the app treats the presence
# of this marker — not the SSH exit code — as success: dartssh2's no-stdin
# exec path reports no exit code on OpenSSH >= 10, but stdout is still captured.
printf 'WG-TRD-OK\n'
