#!/usr/bin/env bash
# Module 40 — write_server_conf: back up any existing configuration, then
# write the server interface file (spec §8.2, RF-13).
# Config: INTERFACE_NAME, WG_PORT, VPN_SUBNET.

run_write_server_conf() {
  local iface=${INTERFACE_NAME:-wg0}
  # WG_ROOT is empty in production; tests set it to sandbox writes.
  local dir=${WG_ROOT:-}/etc/wireguard
  local conf="$dir/${iface}.conf"
  local port=${WG_PORT:-51820}
  local mtu=${MTU:-1420}
  local subnet=${VPN_SUBNET:-10.13.13.0/24}
  local network=${subnet%/*}
  local prefix=${subnet#*/}
  local base=${network%.*}
  if [[ -n ${FAV_CONFIG_VERSION:-} ]]; then
    if [[ ${FAV_CONFIG_VERSION} != 2 ]]; then
      log 'ERR-NET-VERSION-UNSUPPORTED'
      return 42
    fi
    if [[ -e $conf ]]; then
      log 'ERR-NET-UPGRADE-REQUIRED: refusing to replace an existing v2 configuration'
      return 42
    fi
    local helper_dir=${WG_ROOT:-}/etc/wireguard/fav/lib
    install -d -m 700 "$helper_dir"
    install -m 700 "$RUN_DIR/lib/profile_renderer.py" "$helper_dir/profile_renderer.py"
    if ! python3 "$helper_dir/profile_renderer.py" server \
      --result "$RUN_DIR/network-result.json" --keys "$dir" \
      --interface "$iface" --output "$conf"; then
      log 'ERR-NET-PROFILE-INVALID'
      return 42
    fi
    log "Wrote ${conf} from authoritative network result"
    return 0
  fi

  local wan
  wan=$(detect_default_wan)

  # Back up the existing WireGuard config before overwriting it (RF-13).
  if [[ -f "$conf" ]]; then
    local stamp backup
    stamp=$(date -u +%Y%m%d%H%M%S)
    backup="$dir/backups/${stamp}"
    install -d -m 700 "$backup"
    cp -p "$conf" "$backup/"
    log "Backed up existing ${iface}.conf to ${backup}"

    # Rewriting the conf discards the old PostDown, so a live MASQUERADE for
    # a previous subnet/wan pair would linger until reboot — and outlive the
    # teardown, which only removes the current pair (audit F1). Delete it
    # here when the pair changed; `|| true` covers the rule not being live.
    local old_masq old_subnet old_wan
    old_masq=$(grep -m1 '^PostUp = iptables -t nat -C POSTROUTING' "$conf" \
      || true)
    if [[ $old_masq =~ -s\ ([^[:space:]]+)\ -o\ ([^[:space:]]+) ]]; then
      old_subnet=${BASH_REMATCH[1]}
      old_wan=${BASH_REMATCH[2]}
      if [[ $old_subnet != "$subnet" || $old_wan != "$wan" ]]; then
        iptables -t nat -D POSTROUTING -s "$old_subnet" -o "$old_wan" \
          -j MASQUERADE 2>/dev/null || true
        log "Removed stale masquerade for ${old_subnet} via ${old_wan}"
      fi
    fi
  fi

  local server_private client_public preshared
  server_private=$(<"$dir/${iface}_server_private.key")
  client_public=$(<"$dir/${iface}_client_public.key")
  preshared=$(<"$dir/${iface}_client_preshared.key")

  # PostUp/PostDown carry the NAT masquerade and FORWARD rules so wg-quick
  # (re)applies them every time the interface starts — including after a reboot
  # (audit H2; nothing persisted them before). `-C || -A` keeps PostUp
  # idempotent with module 60's runtime application; PostDown removes them and
  # never fails the interface stop. FORWARD ACCEPT is required on hosts whose
  # FORWARD policy is DROP (e.g. Docker).
  umask 077
  cat >"$conf" <<EOF
[Interface]
Address = ${base}.1/${prefix}
ListenPort = ${port}
MTU = ${mtu}
PrivateKey = ${server_private}
PostUp = iptables -t nat -C POSTROUTING -s ${subnet} -o ${wan} -j MASQUERADE 2>/dev/null || iptables -t nat -A POSTROUTING -s ${subnet} -o ${wan} -j MASQUERADE
PostUp = iptables -C FORWARD -i ${iface} -j ACCEPT 2>/dev/null || iptables -A FORWARD -i ${iface} -j ACCEPT
PostUp = iptables -C FORWARD -o ${iface} -j ACCEPT 2>/dev/null || iptables -A FORWARD -o ${iface} -j ACCEPT
PostDown = iptables -t nat -D POSTROUTING -s ${subnet} -o ${wan} -j MASQUERADE 2>/dev/null || true
PostDown = iptables -D FORWARD -i ${iface} -j ACCEPT 2>/dev/null || true
PostDown = iptables -D FORWARD -o ${iface} -j ACCEPT 2>/dev/null || true

[Peer]
PublicKey = ${client_public}
PresharedKey = ${preshared}
AllowedIPs = ${base}.2/32
EOF
  chmod 600 "$conf"
  log "Wrote ${conf}"
}
