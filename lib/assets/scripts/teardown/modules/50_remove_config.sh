#!/usr/bin/env bash
# Teardown 50 — remove_config: remove the WireGuard interface config and the
# server keys FAV generated. Idempotent. Config: INTERFACE_NAME.

run_remove_config() {
  local iface=${INTERFACE_NAME:-wg0}
  local dir=${WG_ROOT:-}/etc/wireguard
  # Remove every piece of FAV key material so nothing is left behind:
  #   - the interface config (${iface}.conf)
  #   - the server/client private+public keys and PSK (30_generate_keys.sh
  #     writes them as `${iface}_*.key`, all chmod 600)
  #   - per-peer client private keys + PSKs (peer_add.sh writes peers/<hash>/)
  #   - config backups holding a previous server private key + PSK
  #     (40_write_server_conf.sh writes backups/<stamp>/)
  #   - the per-interface lock file
  rm -f \
    "$dir/${iface}.conf" \
    "$dir/${iface}.lock" \
    "$dir/${iface}"_*.key
  rm -rf \
    "$dir/peers" \
    "$dir/backups" \
    "$dir/fav/$iface"
  if [[ -d $dir/fav ]] && ! find "$dir/fav" -mindepth 2 -maxdepth 2 -name manifest.json -print -quit | grep -q .; then
    rm -rf "$dir/fav/lib"
  fi
  log "Removed ${iface} config, keys, per-peer secrets and backups"
}
