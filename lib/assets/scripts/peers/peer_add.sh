#!/usr/bin/env bash
# Peer add — v1.1 multi-peer.
#
# Adds a new WireGuard peer to the running interface:
#   1) acquires a per-interface flock so concurrent invocations serialise;
#   2) parses the interface conf to find the smallest free address in
#      VPN_SUBNET;
#   3) generates the client keypair and PSK server-side;
#   4) appends a [Peer] block to the interface conf, prefixed with a
#      sanitised `# label:` comment line for forensic traceability;
#   5) applies the change at runtime with `wg set` (no service restart) and
#      verifies it took via `wg show <iface> peers`;
#   6) emits the resulting client.conf inside a sentinel-delimited envelope
#      to stdout, which the app parses and stores in secure storage.
#
# Required env vars: INTERFACE_NAME, VPN_SUBNET, PUBLIC_ENDPOINT, WG_PORT,
# DNS, MTU, PEER_LABEL. WG_ROOT is empty in production; tests set it to a
# sandbox directory.
#
# Error contract — emits the ERR-xx token to stderr and exits non-zero:
#   exit 40  ERR-PEER-APPLY-FAILED      `wg set` accepted by sandbox but the
#                                       peer didn't appear on the interface
#   exit 41  ERR-PEER-SUBNET-EXHAUSTED  no free host address in VPN_SUBNET
#
# Stdout envelope on success:
#   ADDR=<assigned>/32
#   PUBKEY=<client-public-key>
#   ---BEGIN-CONF---
#   <client.conf body>
#   ---END-CONF---

set -euo pipefail
IFS=$'\n\t'
umask 077

# V2 is a separate, manifest-authoritative protocol. No network/profile value
# supplied by the app is consulted by this branch.
if [[ ${FAV_CONFIG_VERSION:-} == 2 ]]; then
  : "${FAV_INSTALLATION_ID:?FAV_INSTALLATION_ID is required}"
  : "${FAV_OPERATION_ID:?FAV_OPERATION_ID is required}"
  : "${INTERFACE_NAME:?INTERFACE_NAME is required}"
  : "${FAV_PEER_MANAGER:?FAV_PEER_MANAGER is required}"
  _fav_wg_dir="${WG_ROOT:-}/etc/wireguard"
  mkdir -p "$_fav_wg_dir"
  exec 9>"${_fav_wg_dir}/${INTERFACE_NAME}.lock"
  flock -w 30 9 || { printf '%s\n' ERR-PEER-APPLY-FAILED >&2; exit 40; }
  exec python3 "$FAV_PEER_MANAGER" add --interface "$INTERFACE_NAME" \
    --installation "$FAV_INSTALLATION_ID" --operation "$FAV_OPERATION_ID" \
    --label "${PEER_LABEL:-}" --wg-dir "${WG_ROOT:-}/etc/wireguard"
fi

INTERFACE_NAME=${INTERFACE_NAME:?INTERFACE_NAME is required}
VPN_SUBNET=${VPN_SUBNET:?VPN_SUBNET is required}
PUBLIC_ENDPOINT=${PUBLIC_ENDPOINT:?PUBLIC_ENDPOINT is required}
WG_PORT=${WG_PORT:?WG_PORT is required}
DNS=${DNS:?DNS is required}
MTU=${MTU:?MTU is required}
PEER_LABEL=${PEER_LABEL:?PEER_LABEL is required}

# IPv6 endpoint literals need brackets to separate the UDP port.
if [[ $PUBLIC_ENDPOINT == *:* && $PUBLIC_ENDPOINT != \[*\] ]]; then
  PUBLIC_ENDPOINT="[${PUBLIC_ENDPOINT}]"
fi

WG_DIR="${WG_ROOT:-}/etc/wireguard"
CONF="${WG_DIR}/${INTERFACE_NAME}.conf"
LOCK="${WG_DIR}/${INTERFACE_NAME}.lock"

# Sanitised log: never include key material in the message.
log() { printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >&2; }

# Emits an ERR-xx token to stderr and exits with the given code.
die() {
  local code=$1 token=$2
  printf '%s\n' "$token" >&2
  exit "$code"
}

# Returns the smallest free .N in VPN_SUBNET, where .1 is reserved for the
# server. Reads the interface conf only — backup files under
# ${WG_DIR}/backups/ are NOT consulted by design.
find_next_free_ip() {
  local subnet=$1 conf=$2
  local network=${subnet%/*}
  local base=${network%.*}
  local escaped_base=${base//./\\.}
  # Collect used .N from every [Peer] AllowedIPs line whose entry is within
  # the configured subnet. The awk pass below extracts the value side of
  # AllowedIPs assignments, but only while inside a [Peer] block.
  local used="" line entry suffix
  if [[ -f $conf ]]; then
    while IFS= read -r line; do
      # AllowedIPs may be a comma-separated list (e.g. "10.13.13.2/32,
      # 192.168.0.0/24"); split and inspect each entry independently.
      local IFS_BACKUP=$IFS
      IFS=','
      # shellcheck disable=SC2206  # intentional word-split on comma.
      local entries=($line)
      IFS=$IFS_BACKUP
      for entry in "${entries[@]}"; do
        entry=$(printf '%s' "$entry" | tr -d '[:space:]')
        # Match "<base>.<n>/<mask>" — capture the .n part.
        if [[ $entry =~ ^${escaped_base}\.([0-9]+)/[0-9]+$ ]]; then
          suffix=${BASH_REMATCH[1]}
          used+=" ${suffix} "
        fi
      done
    done < <(
      awk '
        /^\[Peer\]/ { in_peer=1; next }
        /^\[/       { in_peer=0; next }
        in_peer && /^[[:space:]]*AllowedIPs[[:space:]]*=/ {
          sub(/^[^=]*=[[:space:]]*/, "")
          print
        }
      ' "$conf"
    )
  fi
  # The server occupies .1; never reassign it.
  used+=" 1 "
  local n
  for ((n = 2; n <= 254; n++)); do
    if [[ $used != *" ${n} "* ]]; then
      printf '%s.%s' "$base" "$n"
      return 0
    fi
  done
  return 1
}

# Sanitises PEER_LABEL down to a small, conf-safe ASCII subset before it
# becomes a `# label:` comment in wg0.conf. Strips every character outside
# `[A-Za-z0-9 ._-]` and clamps to 32 chars — defence in depth against a
# malicious label, since the comment is inside a file we re-read.
sanitised_label() {
  printf '%s' "$PEER_LABEL" | tr -cd '[:alnum:] ._-' | cut -c1-32
}

main() {
  # Acquire the per-interface lock. The redirection opens FD 9 on the lock
  # file; flock takes the FD. Bounded wait (-w) so a wedged holder surfaces as
  # a clean error instead of hanging the app's SSH op forever (audit L3).
  mkdir -p "$WG_DIR"
  exec 9>"$LOCK"
  if ! flock -w 30 9; then
    die 40 "ERR-PEER-APPLY-FAILED"
  fi

  local assigned
  if ! assigned=$(find_next_free_ip "$VPN_SUBNET" "$CONF"); then
    die 41 "ERR-PEER-SUBNET-EXHAUSTED"
  fi
  log "Allocating ${assigned} for new peer"

  # Generate the client keypair and PSK in a per-peer directory mode 0700.
  # The pubkey is short-hashed into the dirname so the directory is stable
  # across runs (revoke can find it).
  local priv pub psk
  priv=$(wg genkey)
  pub=$(printf '%s' "$priv" | wg pubkey)
  psk=$(wg genpsk)
  local pub_short=${pub//[^[:alnum:]]/}
  pub_short=${pub_short:0:12}
  local peer_dir="${WG_DIR}/peers/${pub_short}"

  # Rollback trap: clean up the per-peer dir and any partial [Peer] append
  # if the script is killed (or exits non-zero) between this point and the
  # success-path emission below. Without this, a crash between key write
  # and `wg set` would leave the private key + PSK orphaned on disk while
  # the conf and runtime stay clean (audit M-3).
  local conf_size_before=0
  [[ -f $CONF ]] && conf_size_before=$(wc -c <"$CONF" | tr -d '[:space:]')
  cleanup() {
    rm -rf "$peer_dir"
    if [[ -f $CONF ]]; then
      truncate -s "$conf_size_before" "$CONF" 2>/dev/null || true
    fi
    wg set "$INTERFACE_NAME" peer "$pub" remove >/dev/null 2>&1 || true
  }
  trap cleanup EXIT

  install -d -m 700 "$peer_dir"
  printf '%s\n' "$priv" >"${peer_dir}/private.key"
  printf '%s\n' "$pub"  >"${peer_dir}/public.key"
  printf '%s\n' "$psk"  >"${peer_dir}/preshared.key"
  chmod 600 "${peer_dir}/"*.key

  local label
  label=$(sanitised_label)

  # Append the [Peer] block to the interface conf. The peer block is the
  # unit we rollback on apply failure; the byte offset was captured above
  # so the trap can truncate to it on any exit path.
  {
    printf '\n# label: %s\n' "$label"
    printf '[Peer]\n'
    printf 'PublicKey = %s\n'   "$pub"
    printf 'PresharedKey = %s\n' "$psk"
    printf 'AllowedIPs = %s/32\n' "$assigned"
  } >>"$CONF"
  chmod 600 "$CONF"

  # Apply at runtime — no service restart.
  if ! wg set "$INTERFACE_NAME" \
      peer "$pub" \
      preshared-key "${peer_dir}/preshared.key" \
      allowed-ips "${assigned}/32"; then
    log "wg set failed — rolling back the [Peer] block"
    # The EXIT trap will truncate the conf and remove the peer dir.
    die 40 "ERR-PEER-APPLY-FAILED"
  fi

  # Verify the peer is now on the interface. If not, roll back.
  if ! wg show "$INTERFACE_NAME" peers | grep -qxF "$pub"; then
    log "post-apply verification failed — rolling back the [Peer] block"
    die 40 "ERR-PEER-APPLY-FAILED"
  fi

  # Past this point the change is committed: clear the rollback trap so the
  # envelope emission below cannot accidentally roll back a working peer if
  # the SSH channel breaks mid-write (the client will see a partial conf
  # and re-fetch the peer list — a partial wg0.conf would be worse).
  trap - EXIT

  # Emit the envelope. Sentinels are literal lines: the app strips
  # everything between them and ignores the rest.
  printf 'ADDR=%s/32\n' "$assigned"
  printf 'PUBKEY=%s\n' "$pub"
  printf -- '---BEGIN-CONF---\n'
  cat <<EOF
[Interface]
PrivateKey = ${priv}
Address = ${assigned}/32
DNS = ${DNS}
MTU = ${MTU}

[Peer]
PublicKey = $(<"${WG_DIR}/${INTERFACE_NAME}_server_public.key")
PresharedKey = ${psk}
Endpoint = ${PUBLIC_ENDPOINT}:${WG_PORT}
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF
  printf -- '---END-CONF---\n'
}

main "$@"
