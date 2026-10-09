#!/usr/bin/env bash
# Peer revoke — v1.1 multi-peer.
#
# Removes a WireGuard peer from the running interface and its persistent
# configuration:
#   1) acquires a per-interface flock;
#   2) calls `wg set <iface> peer <pub> remove` to drop the peer from the
#      runtime (does not error if the peer wasn't on the wire);
#   3) strips the matching [Peer] block from <iface>.conf, including the
#      immediately preceding `# label:` comment line if any;
#   4) deletes the per-peer key directory under
#      /etc/wireguard/peers/<pub-shorthash>/ if present.
#
# Required env vars: INTERFACE_NAME, PEER_PUBKEY. WG_ROOT is empty in
# production; tests set it to a sandbox directory.
#
# Exit codes:
#   0   peer removed from at least one of (runtime, conf)
#   42  ERR-PEER-NOT-FOUND  — peer was neither on the wire nor in the conf

set -euo pipefail
IFS=$'\n\t'
umask 077

# V2 is deliberately separate from the legacy best-effort removal below.
if [[ ${FAV_CONFIG_VERSION:-} == 2 ]]; then
  : "${FAV_INSTALLATION_ID:?FAV_INSTALLATION_ID is required}"
  : "${FAV_OPERATION_ID:?FAV_OPERATION_ID is required}"
  : "${INTERFACE_NAME:?INTERFACE_NAME is required}"
  : "${PEER_PUBKEY:?PEER_PUBKEY is required}"
  : "${FAV_PEER_MANAGER:?FAV_PEER_MANAGER is required}"
  _fav_wg_dir="${WG_ROOT:-}/etc/wireguard"
  mkdir -p "$_fav_wg_dir"
  exec 9>"${_fav_wg_dir}/${INTERFACE_NAME}.lock"
  flock -w 30 9 || { printf '%s\n' ERR-PEER-APPLY-FAILED >&2; exit 40; }
  exec python3 "$FAV_PEER_MANAGER" revoke --interface "$INTERFACE_NAME" \
    --installation "$FAV_INSTALLATION_ID" --operation "$FAV_OPERATION_ID" \
    --public-key "$PEER_PUBKEY" --wg-dir "${WG_ROOT:-}/etc/wireguard"
fi

INTERFACE_NAME=${INTERFACE_NAME:?INTERFACE_NAME is required}
PEER_PUBKEY=${PEER_PUBKEY:?PEER_PUBKEY is required}

WG_DIR="${WG_ROOT:-}/etc/wireguard"
CONF="${WG_DIR}/${INTERFACE_NAME}.conf"
LOCK="${WG_DIR}/${INTERFACE_NAME}.lock"

log() { printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >&2; }

die() {
  local code=$1 token=$2
  printf '%s\n' "$token" >&2
  exit "$code"
}

# Strips the [Peer] block whose PublicKey matches $PEER_PUBKEY (exact match,
# whitespace-tolerant around the `=`) from the interface conf, along with
# the immediately preceding `# label:` comment if present. Returns 0 and
# rewrites the conf; sets exit-code via side channel ($removed_from_conf
# global) so the caller knows whether anything matched.
strip_peer_from_conf() {
  local tmp awk_status
  tmp=$(mktemp)
  # awk reads the conf into memory, identifies the [Peer] block matching
  # $pub (whitespace-tolerant on the `PublicKey = <pub>` line), and emits
  # everything except that range. The preceding `# label:` line, if any,
  # is included in the deleted range. A block ends at the next section
  # header (`^[`) OR at a `# label:` line that belongs to the NEXT peer.
  awk_status=0
  awk -v pub="$PEER_PUBKEY" '
    {
      lines[NR] = $0
      total = NR
    }
    END {
      i = 1
      while (i <= total) {
        if (lines[i] ~ /^\[Peer\]/) {
          start = i
          j = i + 1
          while (j <= total && lines[j] !~ /^\[/ && lines[j] !~ /^# label:/) j++
          end = j - 1
          matched = 0
          for (k = start + 1; k <= end; k++) {
            line = lines[k]
            # Match the `PublicKey = <value>` line and compare the WHOLE
            # value. Do NOT split on `=`: real WireGuard keys are base64
            # ending in `=` padding, which a split on `=` would strip, so
            # the comparison would never match a real key (audit C2).
            if (line ~ /^[[:space:]]*[Pp]ublic[Kk]ey[[:space:]]*=/) {
              val = line
              sub(/^[^=]*=[[:space:]]*/, "", val)
              sub(/[[:space:]]+$/, "", val)
              if (val == pub) {
                matched = 1
                break
              }
            }
          }
          if (matched) {
            del_start = start
            if (start > 1 && lines[start - 1] ~ /^# label:/) del_start = start - 1
            for (k = del_start; k <= end; k++) skip[k] = 1
            matches = matches + 1
          }
          i = end + 1
        } else {
          i++
        }
      }
      for (i = 1; i <= total; i++) {
        if (!(i in skip)) print lines[i]
      }
      exit matches > 0 ? 0 : 100
    }
  ' "$CONF" >"$tmp" || awk_status=$?
  if [[ $awk_status -eq 0 ]]; then
    mv "$tmp" "$CONF"
    chmod 600 "$CONF"
    removed_from_conf=1
    return 0
  fi
  if [[ $awk_status -eq 100 ]]; then
    removed_from_conf=0
    rm -f "$tmp"
    return 0
  fi
  rm -f "$tmp"
  log "awk failed with status ${awk_status}"
  return 1
}

main() {
  mkdir -p "$WG_DIR"
  exec 9>"$LOCK"
  # Bounded wait (-w) so a wedged lock holder fails cleanly instead of hanging
  # the app's SSH op forever (audit L3).
  if ! flock -w 30 9; then
    die 42 "ERR-PEER-NOT-FOUND"
  fi

  # Runtime removal — failures are tolerated (peer may already be gone).
  local on_wire=1
  if ! wg set "$INTERFACE_NAME" peer "$PEER_PUBKEY" remove 2>/dev/null; then
    on_wire=0
    log "wg set ... remove failed — assuming peer was not on the wire"
  fi

  # Conf-side removal.
  local removed_from_conf=0
  if [[ -f $CONF ]]; then
    strip_peer_from_conf
  fi

  # Cleanup of per-peer key material, if any. The dirname uses the same
  # short-hash convention as peer_add.sh: alnum-only, first 12 chars.
  local pub_short=${PEER_PUBKEY//[^[:alnum:]]/}
  pub_short=${pub_short:0:12}
  if [[ -n $pub_short && -d "${WG_DIR}/peers/${pub_short}" ]]; then
    rm -rf "${WG_DIR}/peers/${pub_short}"
  fi

  # If neither the runtime nor the conf had the peer, signal not-found.
  if [[ $on_wire == 0 && $removed_from_conf == 0 ]]; then
    die 42 "ERR-PEER-NOT-FOUND"
  fi
}

main "$@"
