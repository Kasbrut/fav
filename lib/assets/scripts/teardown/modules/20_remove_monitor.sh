#!/usr/bin/env bash
# Teardown 20 — remove_monitor: stop, disable and remove the FAV monitor agent
# installed by install_monitor.sh. Idempotent. The WG_MONITOR_* overrides
# mirror install_monitor.sh so BATS can sandbox under WG_ROOT.

run_remove_monitor() {
  local bin=${WG_MONITOR_BIN:-${WG_ROOT:-}/usr/local/bin/wg-monitor.sh}
  local systemd_dir=${WG_MONITOR_SYSTEMD_DIR:-${WG_ROOT:-}/etc/systemd/system}
  local logrotate=${WG_MONITOR_LOGROTATE:-${WG_ROOT:-}/etc/logrotate.d/fav}
  local env_file=${WG_MONITOR_ENV:-${WG_ROOT:-}/etc/fav/monitor.env}
  # Data dirs the monitor writes (mirror wg-monitor.sh's defaults).
  local state_dir=${WG_MONITOR_STATE_DIR:-${WG_ROOT:-}/var/lib/fav}
  local log_dir=${WG_MONITOR_LOG_DIR:-${WG_ROOT:-}/var/log/fav}
  local runtime_dir=${WG_MONITOR_RUNTIME_DIR:-${WG_ROOT:-}/run/fav}

  systemctl disable --now wg-monitor.timer 2>/dev/null || true
  systemctl disable --now wg-monitor.service 2>/dev/null || true

  rm -f \
    "$bin" \
    "$systemd_dir/wg-monitor.service" \
    "$systemd_dir/wg-monitor.timer" \
    "$logrotate" \
    "$env_file"
  # Remove the monitor's snapshot/events/runtime directories (peers-state.json,
  # events.jsonl) — leaving them behind keeps stale peer data on the server.
  rm -rf \
    "$state_dir" \
    "$log_dir" \
    "$runtime_dir"
  # Remove /etc/fav only if now empty (it may hold nothing else).
  rmdir "$(dirname "$env_file")" 2>/dev/null || true

  systemctl daemon-reload 2>/dev/null || true
  log 'Monitor agent and data removed'
}
