#!/usr/bin/env bash
# Module 90 — health_check: verify the WireGuard interface is up and the
# listen port is open (spec §8.2, RF-15). Config: INTERFACE_NAME, WG_PORT.

run_health_check() {
  local iface=${INTERFACE_NAME:-wg0}
  local port=${WG_PORT:-51820}
  if ! wg show "$iface" >/dev/null 2>&1; then
    log "wg show ${iface} failed"
    return 1
  fi
  if ! ss -lun 2>/dev/null | awk '{print $4}' | grep -q ":${port}\$"; then
    log "UDP port ${port} is not listening"
    return 1
  fi
  log "Health check passed: ${iface} up, UDP ${port} listening"
}
