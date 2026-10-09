#!/usr/bin/env bash
# Module 30 — generate_keys: create the server and first-client WireGuard
# keys and the preshared key (spec §8.2). Config: INTERFACE_NAME.

run_generate_keys() {
  local iface=${INTERFACE_NAME:-wg0}
  # WG_ROOT is empty in production; tests set it to sandbox writes.
  local dir=${WG_ROOT:-}/etc/wireguard
  install -d -m 700 "$dir"
  umask 077

  if [[ ! -s "$dir/${iface}_server_private.key" ]]; then
    wg genkey >"$dir/${iface}_server_private.key"
  fi
  wg pubkey <"$dir/${iface}_server_private.key" \
    >"$dir/${iface}_server_public.key"

  if [[ ! -s "$dir/${iface}_client_private.key" ]]; then
    wg genkey >"$dir/${iface}_client_private.key"
  fi
  wg pubkey <"$dir/${iface}_client_private.key" \
    >"$dir/${iface}_client_public.key"

  if [[ ! -s "$dir/${iface}_client_preshared.key" ]]; then
    wg genpsk >"$dir/${iface}_client_preshared.key"
  fi
  # Restrict the key files explicitly, independent of the umask above.
  chmod 600 "$dir/${iface}"_*.key
  log "WireGuard keys ready for ${iface}"
}
