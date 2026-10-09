#!/usr/bin/env bash
# Module 60 — firewall: apply the NAT masquerade + FORWARD rules for the VPN
# subnet at runtime so traffic flows immediately, before wg-quick restarts.
# Persistence across reboots lives in the interface conf's PostUp/PostDown
# (module 40), so no netfilter-persistent package is needed. Config: VPN_SUBNET.

run_firewall() {
  if [[ -n ${FAV_CONFIG_VERSION:-} ]]; then
    local iface=${INTERFACE_NAME:-wg0}
    python3 "${WG_ROOT:-}/etc/wireguard/fav/lib/firewall_manager.py" apply \
      --manifest "${WG_ROOT:-}/etc/wireguard/fav/$iface/manifest.json"
    log "V2 firewall reconciled without duplicate rules"
    return 0
  fi
  local subnet=${VPN_SUBNET:-10.13.13.0/24}
  local iface=${INTERFACE_NAME:-wg0}
  local wan
  wan=$(detect_default_wan)

  # Add each rule only if it is not already present (idempotent, and safe
  # against the same rule wg-quick's PostUp adds when the service starts).
  if ! iptables -t nat -C POSTROUTING -s "$subnet" -o "$wan" \
    -j MASQUERADE 2>/dev/null; then
    iptables -t nat -A POSTROUTING -s "$subnet" -o "$wan" -j MASQUERADE
  fi
  if ! iptables -C FORWARD -i "$iface" -j ACCEPT 2>/dev/null; then
    iptables -A FORWARD -i "$iface" -j ACCEPT
  fi
  if ! iptables -C FORWARD -o "$iface" -j ACCEPT 2>/dev/null; then
    iptables -A FORWARD -o "$iface" -j ACCEPT
  fi
  log "NAT masquerade + forwarding configured for ${subnet} via ${wan}"
}
