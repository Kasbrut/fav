#!/usr/bin/env bash
# Teardown 10 — stop_service: stop and disable the WireGuard service.
# Idempotent: tolerates a unit that is already gone. Config: INTERFACE_NAME.

run_stop_service() {
  local iface=${INTERFACE_NAME:-wg0}
  local unit="wg-quick@${iface}"
  systemctl disable --now "$unit" 2>/dev/null || true
  log "${unit} stopped and disabled"
}
