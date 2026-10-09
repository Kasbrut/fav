#!/usr/bin/env bash
# Install v2 deny-first policy before forwarding can be enabled.
run_firewall_guard() {
  [[ -z ${FAV_CONFIG_VERSION:-} ]] && return 0
  local iface=${INTERFACE_NAME:-wg0}
  local root=${WG_ROOT:-}/etc/wireguard/fav
  local manifest="$root/$iface/manifest.json"
  install -d -m 700 "$root/lib" "$root/$iface"
  install -m 700 "$RUN_DIR/lib/firewall_manager.py" "$root/lib/firewall_manager.py"
  python3 "$RUN_DIR/lib/profile_renderer.py" manifest --result "$RUN_DIR/network-result.json" \
    --keys "${WG_ROOT:-}/etc/wireguard" --interface "$iface" --output "$manifest"
  python3 "$root/lib/firewall_manager.py" apply --manifest "$manifest"
  log "IPv6 firewall guard installed from authoritative manifest"
}
