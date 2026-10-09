#!/usr/bin/env bash
# Module 50 — enable_forwarding: turn on IPv4 forwarding (spec §8.2).

run_enable_forwarding() {
  if [[ -n ${FAV_CONFIG_VERSION:-} ]]; then
    log "Forwarding state recorded and applied by v2 firewall guard"
    return 0
  fi
  # WG_ROOT is empty in production; tests set it to sandbox writes.
  local file=${WG_ROOT:-}/etc/sysctl.d/99-wireguard.conf
  install -d -m 755 "$(dirname "$file")"
  printf 'net.ipv4.ip_forward = 1\n' >"$file"
  sysctl -p "$file" >/dev/null
  log "IPv4 forwarding enabled"
}
