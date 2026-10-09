#!/usr/bin/env bash
# Module 70 — start_service: enable and start the WireGuard service, then
# verify it is active (spec §8.2). Config: INTERFACE_NAME.

configure_wg_quick_apparmor() {
  local root=${WG_ROOT:-}
  local profile=${WG_QUICK_APPARMOR_PROFILE:-$root/etc/apparmor.d/wg-quick}
  local local_rule=${WG_QUICK_APPARMOR_LOCAL_RULE:-$root/etc/apparmor.d/local/wg-quick}

  [[ -f $profile ]] || return 0
  grep -q 'include if exists <local/wg-quick>' "$profile" || return 0

  install -d -m 755 "$(dirname "$local_rule")"
  printf '%s\n' \
    '# Managed by FAV: trusted root-owned firewall helper called by wg-quick.' \
    '/usr/bin/python3 rPUx,' \
    '/usr/bin/python3.[0-9]* rPUx,' >"$local_rule"
  chmod 644 "$local_rule"
  apparmor_parser -r "$profile"
}

run_start_service() {
  local iface=${INTERFACE_NAME:-wg0}
  local unit="wg-quick@${iface}"
  configure_wg_quick_apparmor
  systemctl enable "$unit"
  # restart, not `enable --now`: `--now` only *starts* an inactive unit, so a
  # re-install over an already-up interface would keep the stale runtime config
  # (changed subnet/port/keys). restart re-reads the freshly written conf and
  # re-runs PostUp (audit M-restart).
  systemctl restart "$unit"
  if ! systemctl is-active --quiet "$unit"; then
    log "${unit} is not active after starting it"
    return 1
  fi
  log "${unit} is active"
}
