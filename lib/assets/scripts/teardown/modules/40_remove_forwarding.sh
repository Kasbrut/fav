#!/usr/bin/env bash
# Teardown 40 — remove_forwarding: remove the IPv4-forwarding sysctl drop-in
# FAV wrote and reload sysctl. Idempotent. Leaves the running value alone if
# the operator set it elsewhere — only the FAV drop-in is removed.

run_remove_forwarding() {
  local iface=${INTERFACE_NAME:-wg0}
  if [[ -e ${WG_ROOT:-}/etc/wireguard/fav/$iface/manifest.json ]]; then
    log 'V2 forwarding sysctls already restored from manifest'
    return 0
  fi
  local file=${WG_ROOT:-}/etc/sysctl.d/99-wireguard.conf
  if [[ -e $file ]]; then
    rm -f "$file"
    log "Removed ${file}"
  else
    log 'IPv4-forwarding drop-in not present, skipping'
  fi
  sysctl --system >/dev/null 2>&1 || true
}
