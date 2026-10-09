#!/usr/bin/env bash
# Module 99 — finalize: generate the first client profile (spec §8.2, RF-16).
# The orchestrator's EXIT trap writes the exit-code file; the app removes the
# run directory after reading client.conf. Config: INTERFACE_NAME, WG_PORT,
# VPN_SUBNET, DNS, PUBLIC_ENDPOINT.

run_finalize() {
  local iface=${INTERFACE_NAME:-wg0}
  # WG_ROOT is empty in production; tests set it to sandbox writes.
  local dir=${WG_ROOT:-}/etc/wireguard
  local subnet=${VPN_SUBNET:-10.13.13.0/24}
  local base=${subnet%.*}
  local port=${WG_PORT:-51820}
  local mtu=${MTU:-1420}
  local dns=${DNS:-1.1.1.1, 1.0.0.1}
  local endpoint=${PUBLIC_ENDPOINT:-}

  if [[ -n ${FAV_CONFIG_VERSION:-} ]]; then
    if [[ ${FAV_CONFIG_VERSION} != 2 ]]; then
      log 'ERR-NET-VERSION-UNSUPPORTED'
      return 42
    fi
    local helper=${WG_ROOT:-}/etc/wireguard/fav/lib/profile_renderer.py
    local manifest=${WG_ROOT:-}/etc/wireguard/fav/${iface}/manifest.json
    if [[ ! -x $helper ]]; then
      log 'ERR-NET-PROFILE-INVALID: persistent renderer missing'
      return 42
    fi
    if ! python3 "$helper" client --result "$RUN_DIR/network-result.json" \
      --keys "$dir" --interface "$iface" --output "$RUN_DIR/client.conf" \
      --manifest "$manifest"; then
      log 'ERR-NET-PROFILE-INVALID'
      return 42
    fi
    log "Client profile written to ${RUN_DIR}/client.conf"
    return 0
  fi
  # An empty endpoint would emit an unusable `Endpoint = :<port>` profile and
  # still report success. The app defaults this to the server host, but fail
  # loudly here too rather than ship a broken client.conf (audit L2).
  if [[ -z $endpoint ]]; then
    log 'PUBLIC_ENDPOINT is empty; refusing to write an unusable client profile'
    return 1
  fi

# IPv6 endpoint literals need brackets to separate the UDP port.
if [[ $endpoint == *:* && $endpoint != \[*\] ]]; then
  endpoint="[${endpoint}]"
fi

  local client_private server_public preshared
  client_private=$(<"$dir/${iface}_client_private.key")
  server_public=$(<"$dir/${iface}_server_public.key")
  preshared=$(<"$dir/${iface}_client_preshared.key")

  local out="${RUN_DIR:?RUN_DIR is required}/client.conf"
  umask 077
  cat >"$out" <<EOF
[Interface]
PrivateKey = ${client_private}
Address = ${base}.2/32
DNS = ${dns}
MTU = ${mtu}

[Peer]
PublicKey = ${server_public}
PresharedKey = ${preshared}
Endpoint = ${endpoint}:${port}
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF
  chmod 600 "$out"
  log "Client profile written to ${out}"
}
