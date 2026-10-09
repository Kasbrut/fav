#!/usr/bin/env bash
# Teardown 30 — remove_firewall: delete the NAT masquerade + FORWARD rules FAV
# added. Belt-and-braces: the interface's PostDown (module 40 of the installer)
# already removes them when the service is stopped (teardown 10), so this only
# clears anything that outlived it. Idempotent: removes each rule only while it
# is present. Config: VPN_SUBNET, INTERFACE_NAME.

run_remove_firewall() {
  local iface=${INTERFACE_NAME:-wg0}
  local root=${WG_ROOT:-}/etc/wireguard/fav
  local manifest="$root/$iface/manifest.json"
  if [[ -e $manifest || -L $manifest ]]; then
    local helper="$RUN_DIR/lib/firewall_manager.py"
    [[ -r $helper ]] || { log 'ERR-NET-FIREWALL-UNSUPPORTED: helper missing'; return 42; }
    python3 "$helper" remove --manifest "$manifest"
    log "V2 manifest-owned firewall resources removed"
    return 0
  fi
  local subnet=${VPN_SUBNET:-10.13.13.0/24}
  local iface=${INTERFACE_NAME:-wg0}
  local wan
  wan=$(detect_default_wan)

  # -D repeatedly until the (possibly duplicated) rule is gone.
  while iptables -t nat -C POSTROUTING -s "$subnet" -o "$wan" \
    -j MASQUERADE 2>/dev/null; do
    iptables -t nat -D POSTROUTING -s "$subnet" -o "$wan" -j MASQUERADE
  done
  while iptables -C FORWARD -i "$iface" -j ACCEPT 2>/dev/null; do
    iptables -D FORWARD -i "$iface" -j ACCEPT
  done
  while iptables -C FORWARD -o "$iface" -j ACCEPT 2>/dev/null; do
    iptables -D FORWARD -o "$iface" -j ACCEPT
  done
  log "NAT masquerade + forwarding rules for ${subnet} via ${wan} removed"
}
