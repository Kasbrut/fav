#!/usr/bin/env bash
# WireGuard peer monitor (M15-T2). Driven by wg-monitor.timer every 30s.
#
# Reads `wg show <iface> dump`, writes an atomic JSON snapshot of peer state
# under StateDirectory, and appends connect/disconnect events to a JSONL
# log under LogsDirectory. Events older than 7 days are trimmed in-place.
#
# Idempotent. Safe to re-run. Holds a non-blocking flock so a concurrent
# timer/manual invocation does not corrupt the snapshot.

set -euo pipefail
IFS=$'\n\t'

# Restrict the mode of every file we create from here on: snapshot/events/prev
# files must be 0640 the moment they exist, not after a post-write chmod (M15
# security audit fix #3).
umask 027

# Overridable env (used by the BATS suite). Defaults match the values set up
# by the systemd unit via StateDirectory/LogsDirectory/RuntimeDirectory.
WG_MONITOR_STATE_DIR=${WG_MONITOR_STATE_DIR:-/var/lib/fav}
WG_MONITOR_LOG_DIR=${WG_MONITOR_LOG_DIR:-/var/log/fav}
WG_MONITOR_RUNTIME_DIR=${WG_MONITOR_RUNTIME_DIR:-/run/fav}
WG_MONITOR_ENV=${WG_MONITOR_ENV:-/etc/fav/monitor.env}
WG_MONITOR_VERSION=${WG_MONITOR_VERSION:-1.0.0}

# Defaults that the env file may override (NEW_USERNAME, WG_INTERFACE).
NEW_USERNAME=""
WG_INTERFACE="wg0"
if [[ -f $WG_MONITOR_ENV ]]; then
  # shellcheck disable=SC1090
  source "$WG_MONITOR_ENV"
fi
WG_INTERFACE=${WG_INTERFACE:-wg0}

STATE_FILE="$WG_MONITOR_STATE_DIR/peers-state.json"
PREV_FILE="$WG_MONITOR_STATE_DIR/peers-state.prev.tsv"
EVENTS_FILE="$WG_MONITOR_LOG_DIR/events.jsonl"
LOCK_FILE="$WG_MONITOR_RUNTIME_DIR/wg-monitor.lock"

mkdir -p "$WG_MONITOR_STATE_DIR" "$WG_MONITOR_LOG_DIR" "$WG_MONITOR_RUNTIME_DIR"

# Forbid overlapping invocations: a manual debug run alongside the timer must
# not interleave with the atomic snapshot write. `flock` is always present on
# Debian/Ubuntu (util-linux); the `command -v` guard keeps the BATS suite
# usable on hosts without it (e.g. a stock macOS workstation).
if command -v flock >/dev/null 2>&1; then
  exec 9>"$LOCK_FILE"
  if ! flock -n 9; then
    exit 0
  fi
fi

now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }
now_unix() { date -u +%s; }

# JSON-escape a string for inclusion in a double-quoted JSON value.
json_escape() {
  local value=$1
  value=${value//\\/\\\\}
  value=${value//\"/\\\"}
  value=${value//[[:cntrl:]]/ }
  printf '%s' "$value"
}

# Compute the cutoff ISO timestamp (7 days ago, UTC). GNU and BSD `date` use
# different flags; try both so the script runs on Debian (GNU) and macOS (BSD)
# unchanged.
iso_seven_days_ago() {
  date -u -d '7 days ago' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
    || date -u -v-7d +%Y-%m-%dT%H:%M:%SZ
}

# Capture `wg show <iface> dump`. When the interface is down, `wg` exits
# non-zero — keep going so the snapshot still lands (peers list empty) and the
# app can tell the agent itself is alive.
dump_raw=$(wg show "$WG_INTERFACE" dump 2>/dev/null || true)

iface_private_key="" iface_public_key="" iface_listen_port="" iface_fwmark=""
peer_lines=()
if [[ -n $dump_raw ]]; then
  line_no=0
  while IFS= read -r line; do
    line_no=$((line_no + 1))
    if [[ $line_no -eq 1 ]]; then
      IFS=$'\t' read -r iface_private_key iface_public_key iface_listen_port iface_fwmark <<<"$line"
    else
      peer_lines+=("$line")
    fi
  done <<<"$dump_raw"
fi
# M15-T10 security audit fix #5: the interface private key is never used past
# this point; drop it from the shell environment so a future `set -x` debug
# session cannot inadvertently echo it.
unset iface_private_key iface_fwmark

generated_at=$(now_iso)
unix_now=$(now_unix)
fresh_threshold=180

# Pre-load previous peer state for delta + transition detection. The `|| [[ -n
# $p_key ]]` is the standard idiom for reading files whose last line lacks a
# trailing newline (which our atomic-write path can produce).
declare -A prev_online prev_rx prev_tx
if [[ -f $PREV_FILE ]]; then
  while IFS=$'\t' read -r p_key p_online p_rx p_tx _p_latest || [[ -n $p_key ]]; do
    [[ -z $p_key ]] && continue
    prev_online[$p_key]=$p_online
    prev_rx[$p_key]=$p_rx
    prev_tx[$p_key]=$p_tx
  done <"$PREV_FILE"
fi

snapshot_peers_json=""
new_prev=""
events_to_emit=()
first_peer=1

for line in "${peer_lines[@]}"; do
  [[ -z $line ]] && continue
  IFS=$'\t' read -r peer_pubkey _peer_preshared peer_endpoint peer_allowed peer_latest peer_rx peer_tx _peer_keepalive <<<"$line"
  [[ -z $peer_pubkey ]] && continue

  # Online predicate (see milestone doc + M15-T11 fix):
  # - `online_by_handshake`: latest handshake within `fresh_threshold` (180s).
  # - `online_by_traffic`: rx OR tx grew since the previous tick. The arm
  #   only fires when we have a prior observation — at the first sight of
  #   a peer, the cumulative rx/tx may reflect history from before the
  #   monitor started and must not be read as fresh traffic.
  # - For a peer that was previously observed ONLINE, we require
  #   `online_by_traffic` to stay online. The kernel preserves the last
  #   handshake counter for up to ~3 minutes after the client disconnects,
  #   and that window would mask a rapid disconnect/reconnect cycle (the
  #   client refreshes the handshake on reconnect before staleness kicks
  #   in, so the agent would never see the offline transition). The
  #   mandatory `PersistentKeepalive = 25` on every client config produced
  #   by `99_finalize.sh` guarantees a real connected client shows traffic
  #   growth on every 30s tick — no growth on a tick means the peer is
  #   gone, regardless of how recent the handshake counter looks.
  # - For a peer that was previously OFFLINE or never observed, either
  #   signal (fresh handshake or traffic growth) flips it to online; the
  #   delta arm catches reconnects that arrive between the rekey window
  #   and the next tick.
  online_by_handshake="false"
  if [[ ${peer_latest:-0} -gt 0 ]]; then
    age=$((unix_now - peer_latest))
    if [[ $age -ge 0 && $age -lt $fresh_threshold ]]; then
      online_by_handshake="true"
    fi
  fi
  online_by_traffic="false"
  if [[ -n ${prev_online[$peer_pubkey]:-} ]]; then
    pr=${prev_rx[$peer_pubkey]:-0}
    pt=${prev_tx[$peer_pubkey]:-0}
    if [[ ${peer_rx:-0} -gt $pr || ${peer_tx:-0} -gt $pt ]]; then
      online_by_traffic="true"
    fi
  fi
  if [[ ${prev_online[$peer_pubkey]:-} == true ]]; then
    online=$online_by_traffic
  else
    if [[ $online_by_handshake == true || $online_by_traffic == true ]]; then
      online="true"
    else
      online="false"
    fi
  fi

  # Transitions only — the first observation of a peer never emits an event,
  # so a reboot does not produce a flood of "connect"s for already-connected
  # clients.
  if [[ -n ${prev_online[$peer_pubkey]:-} ]]; then
    if [[ ${prev_online[$peer_pubkey]} == false && $online == true ]]; then
      events_to_emit+=("connect|$peer_pubkey|${peer_rx:-0}|${peer_tx:-0}|${peer_latest:-0}")
    elif [[ ${prev_online[$peer_pubkey]} == true && $online == false ]]; then
      events_to_emit+=("disconnect|$peer_pubkey|${peer_rx:-0}|${peer_tx:-0}|${peer_latest:-0}")
    fi
  fi

  allowed_json="["
  if [[ -n ${peer_allowed:-} && $peer_allowed != "(none)" ]]; then
    IFS=',' read -ra allowed_arr <<<"$peer_allowed"
    first_ip=1
    for ip in "${allowed_arr[@]}"; do
      ip_trimmed=${ip# }
      ip_trimmed=${ip_trimmed% }
      if [[ $first_ip -eq 0 ]]; then
        allowed_json+=","
      fi
      allowed_json+="\"$(json_escape "$ip_trimmed")\""
      first_ip=0
    done
  fi
  allowed_json+="]"

  endpoint_json="null"
  if [[ -n ${peer_endpoint:-} && $peer_endpoint != "(none)" ]]; then
    endpoint_json="\"$(json_escape "$peer_endpoint")\""
  fi

  if [[ $first_peer -eq 0 ]]; then
    snapshot_peers_json+=","
  fi
  first_peer=0
  snapshot_peers_json+=$(printf '{"publicKey":"%s","endpoint":%s,"allowedIps":%s,"latestHandshake":%s,"rx":%s,"tx":%s,"online":%s}' \
    "$(json_escape "$peer_pubkey")" "$endpoint_json" "$allowed_json" \
    "${peer_latest:-0}" "${peer_rx:-0}" "${peer_tx:-0}" "$online")

  # `$(...)` strips trailing newlines — append the record and a literal
  # newline separately so the prev file is line-terminated correctly.
  new_prev+="$(printf '%s\t%s\t%s\t%s\t%s' "$peer_pubkey" "$online" "${peer_rx:-0}" "${peer_tx:-0}" "${peer_latest:-0}")"
  new_prev+=$'\n'
done

iface_json="null"
if [[ -n $iface_public_key ]]; then
  iface_json=$(printf '{"publicKey":"%s","listenPort":%s}' \
    "$(json_escape "$iface_public_key")" "${iface_listen_port:-0}")
fi

snapshot_json=$(printf '{"schemaVersion":1,"monitorVersion":"%s","generatedAt":"%s","interface":%s,"peers":[%s]}\n' \
  "$(json_escape "$WG_MONITOR_VERSION")" "$generated_at" "$iface_json" "$snapshot_peers_json")

# Atomic snapshot write.
tmp="$STATE_FILE.tmp"
printf '%s' "$snapshot_json" >"$tmp"
mv -f "$tmp" "$STATE_FILE"

# Update the prev-state TSV (private; only used by the script).
prev_tmp="$PREV_FILE.tmp"
printf '%s' "$new_prev" >"$prev_tmp"
mv -f "$prev_tmp" "$PREV_FILE"

# Append transition events.
if [[ ${#events_to_emit[@]} -gt 0 ]]; then
  touch "$EVENTS_FILE"
  for event in "${events_to_emit[@]}"; do
    IFS='|' read -r evt_type evt_pubkey evt_rx evt_tx evt_latest <<<"$event"
    printf '{"serverTimestamp":"%s","publicKey":"%s","type":"%s","rx":%s,"tx":%s,"latestHandshake":%s}\n' \
      "$generated_at" "$(json_escape "$evt_pubkey")" "$evt_type" "$evt_rx" "$evt_tx" "$evt_latest" >>"$EVENTS_FILE"
  done
fi

# Trim events older than 7 days. ISO-8601 UTC strings of fixed width are safe
# to compare lexicographically.
if [[ -s ${EVENTS_FILE:-/dev/null} ]]; then
  cutoff=$(iso_seven_days_ago)
  awk -v cutoff="$cutoff" '
    {
      ts = $0
      sub(/.*"serverTimestamp":"/, "", ts)
      sub(/".*/, "", ts)
      if (ts >= cutoff) print
    }
  ' "$EVENTS_FILE" >"$EVENTS_FILE.tmp"
  mv -f "$EVENTS_FILE.tmp" "$EVENTS_FILE"
fi

# Defensive perms — keep the snapshot and events readable by the login user
# even after a usermod or a manual chmod that drifted from the install-time
# defaults. Tolerates a missing or renamed user without failing the run.
chmod 0640 "$STATE_FILE" 2>/dev/null || true
chmod 0640 "$PREV_FILE" 2>/dev/null || true
[[ -f $EVENTS_FILE ]] && chmod 0640 "$EVENTS_FILE" 2>/dev/null || true
if [[ -n $NEW_USERNAME && $NEW_USERNAME != root ]] \
  && getent passwd "$NEW_USERNAME" >/dev/null 2>&1; then
  chown root:"$NEW_USERNAME" "$STATE_FILE" 2>/dev/null || true
  chown root:"$NEW_USERNAME" "$PREV_FILE" 2>/dev/null || true
  [[ -f $EVENTS_FILE ]] \
    && chown root:"$NEW_USERNAME" "$EVENTS_FILE" 2>/dev/null || true
fi
