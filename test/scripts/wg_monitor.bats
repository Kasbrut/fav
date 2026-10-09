#!/usr/bin/env bats
# Tests for wg-monitor.sh (M15-T2): wg-dump parsing, online predicate,
# connect/disconnect transitions, retention.

load test_helper

WG_MONITOR_SCRIPT="$(cd "${BATS_TEST_DIRNAME}/../../lib/assets/scripts" && pwd)/wg-monitor.sh"

setup() {
  install_mocks "$BATS_TEST_TMPDIR/bin"
  export PATH
  export MOCK_LOG="$BATS_TEST_TMPDIR/mock.log"
  : >"$MOCK_LOG"

  export WG_MONITOR_STATE_DIR="$BATS_TEST_TMPDIR/state"
  export WG_MONITOR_LOG_DIR="$BATS_TEST_TMPDIR/log"
  export WG_MONITOR_RUNTIME_DIR="$BATS_TEST_TMPDIR/run"
  # Point the env file at /dev/null so the script does not pick up local
  # /etc/fav/monitor.env on the developer machine.
  export WG_MONITOR_ENV='/dev/null'
  export WG_MONITOR_VERSION='test'
}

# Compose a `wg show wg0 dump` payload. First arg is the interface line
# (4 tab-separated fields); the rest are peer lines (8 tab-separated fields).
build_dump() {
  local iface=$1
  shift
  printf '%s' "$iface"
  for line in "$@"; do
    printf '\n%s' "$line"
  done
}

run_monitor() {
  run env \
    WG_MONITOR_STATE_DIR="$WG_MONITOR_STATE_DIR" \
    WG_MONITOR_LOG_DIR="$WG_MONITOR_LOG_DIR" \
    WG_MONITOR_RUNTIME_DIR="$WG_MONITOR_RUNTIME_DIR" \
    WG_MONITOR_ENV="$WG_MONITOR_ENV" \
    WG_MONITOR_VERSION="$WG_MONITOR_VERSION" \
    PATH="$PATH" \
    MOCK_LOG="$MOCK_LOG" \
    MOCK_WG_DUMP="$MOCK_WG_DUMP" \
    bash "$WG_MONITOR_SCRIPT"
}

@test "writes an empty snapshot when wg is unavailable" {
  unset MOCK_WG_DUMP
  export MOCK_WG_DUMP=''
  run_monitor
  [ "$status" -eq 0 ]
  [ -f "$WG_MONITOR_STATE_DIR/peers-state.json" ]
  grep -q '"schemaVersion":1' "$WG_MONITOR_STATE_DIR/peers-state.json"
  grep -q '"peers":\[\]' "$WG_MONITOR_STATE_DIR/peers-state.json"
  grep -q '"interface":null' "$WG_MONITOR_STATE_DIR/peers-state.json"
  # No events on the first observation.
  [ ! -s "$WG_MONITOR_LOG_DIR/events.jsonl" ] || true
}

@test "snapshot reports a peer with a fresh handshake as online" {
  now=$(date -u +%s)
  iface=$(printf '%s\t%s\t%s\t%s' '(none)' 'srv_pub_key' '51820' 'off')
  peer=$(printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s' \
    'peer1_pubkey' '(none)' '1.2.3.4:51820' '10.13.13.2/32' "$now" '1024' '2048' '25')
  export MOCK_WG_DUMP="$(build_dump "$iface" "$peer")"
  run_monitor
  [ "$status" -eq 0 ]
  grep -q '"publicKey":"peer1_pubkey"' "$WG_MONITOR_STATE_DIR/peers-state.json"
  grep -q '"online":true' "$WG_MONITOR_STATE_DIR/peers-state.json"
  grep -q '"endpoint":"1.2.3.4:51820"' "$WG_MONITOR_STATE_DIR/peers-state.json"
  grep -q '"allowedIps":\["10.13.13.2/32"\]' "$WG_MONITOR_STATE_DIR/peers-state.json"
  grep -q '"interface":{"publicKey":"srv_pub_key","listenPort":51820}' \
    "$WG_MONITOR_STATE_DIR/peers-state.json"
  # First observation never emits a transition event.
  [ ! -s "$WG_MONITOR_LOG_DIR/events.jsonl" ] || true
}

@test "snapshot reports a peer with a stale handshake as offline" {
  past=$(($(date -u +%s) - 600))
  iface=$(printf '%s\t%s\t%s\t%s' '(none)' 'srv_pub_key' '51820' 'off')
  peer=$(printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s' \
    'peer1_pubkey' '(none)' '1.2.3.4:51820' '10.13.13.2/32' "$past" '1024' '2048' '25')
  export MOCK_WG_DUMP="$(build_dump "$iface" "$peer")"
  run_monitor
  [ "$status" -eq 0 ]
  grep -q '"online":false' "$WG_MONITOR_STATE_DIR/peers-state.json"
}

@test "traffic delta marks an idle-but-up peer as online on the second run" {
  past=$(($(date -u +%s) - 600))
  iface=$(printf '%s\t%s\t%s\t%s' '(none)' 'srv_pub_key' '51820' 'off')
  # First run: stale handshake, low byte counters → offline.
  peer1=$(printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s' \
    'peer1' '(none)' '1.2.3.4:51820' '10.13.13.2/32' "$past" '1024' '2048' '25')
  export MOCK_WG_DUMP="$(build_dump "$iface" "$peer1")"
  run_monitor
  grep -q '"online":false' "$WG_MONITOR_STATE_DIR/peers-state.json"
  # Second run: still stale handshake but rx/tx grew → delta arm fires.
  peer2=$(printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s' \
    'peer1' '(none)' '1.2.3.4:51820' '10.13.13.2/32' "$past" '5000' '8000' '25')
  export MOCK_WG_DUMP="$(build_dump "$iface" "$peer2")"
  run_monitor
  grep -q '"online":true' "$WG_MONITOR_STATE_DIR/peers-state.json"
  # Transition offline → online produces a `connect` event.
  [ -s "$WG_MONITOR_LOG_DIR/events.jsonl" ]
  grep -q '"type":"connect"' "$WG_MONITOR_LOG_DIR/events.jsonl"
  grep -q '"publicKey":"peer1"' "$WG_MONITOR_LOG_DIR/events.jsonl"
}

@test "emits a disconnect event when a peer goes from fresh to stale" {
  now=$(date -u +%s)
  iface=$(printf '%s\t%s\t%s\t%s' '(none)' 'srv_pub_key' '51820' 'off')
  peer_fresh=$(printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s' \
    'peer1' '(none)' '1.2.3.4:51820' '10.13.13.2/32' "$now" '1024' '2048' '25')
  export MOCK_WG_DUMP="$(build_dump "$iface" "$peer_fresh")"
  run_monitor
  # Second run: handshake far in the past + no traffic delta → offline.
  past=$((now - 600))
  peer_stale=$(printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s' \
    'peer1' '(none)' '1.2.3.4:51820' '10.13.13.2/32' "$past" '1024' '2048' '25')
  export MOCK_WG_DUMP="$(build_dump "$iface" "$peer_stale")"
  run_monitor
  [ -s "$WG_MONITOR_LOG_DIR/events.jsonl" ]
  grep -q '"type":"disconnect"' "$WG_MONITOR_LOG_DIR/events.jsonl"
  grep -q '"publicKey":"peer1"' "$WG_MONITOR_LOG_DIR/events.jsonl"
}

@test "emits a disconnect on the next tick when traffic stops despite a fresh handshake" {
  # Regression for M15-T11: the kernel holds the last handshake counter
  # for up to ~3 minutes after a client disconnects, so handshake age
  # alone is too slow to detect a rapid disconnect/reconnect cycle.
  # PersistentKeepalive=25 (forced by 99_finalize.sh) makes a connected
  # client grow rx every 30s tick — no growth means the peer is gone.
  now=$(date -u +%s)
  iface=$(printf '%s\t%s\t%s\t%s' '(none)' 'srv_pub_key' '51820' 'off')
  peer_active=$(printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s' \
    'peer1' '(none)' '1.2.3.4:51820' '10.13.13.2/32' "$now" '1000' '2000' '25')
  export MOCK_WG_DUMP="$(build_dump "$iface" "$peer_active")"
  run_monitor
  peer_growing=$(printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s' \
    'peer1' '(none)' '1.2.3.4:51820' '10.13.13.2/32' "$now" '1500' '2500' '25')
  export MOCK_WG_DUMP="$(build_dump "$iface" "$peer_growing")"
  run_monitor
  # No event yet — handshake fresh AND traffic growing → still online.
  if [ -f "$WG_MONITOR_LOG_DIR/events.jsonl" ]; then
    [ ! -s "$WG_MONITOR_LOG_DIR/events.jsonl" ]
  fi
  # Third run: handshake still fresh (kernel hasn't expired it yet) but
  # rx/tx no longer growing → disconnect detected immediately.
  peer_frozen=$(printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s' \
    'peer1' '(none)' '1.2.3.4:51820' '10.13.13.2/32' "$now" '1500' '2500' '25')
  export MOCK_WG_DUMP="$(build_dump "$iface" "$peer_frozen")"
  run_monitor
  [ -s "$WG_MONITOR_LOG_DIR/events.jsonl" ]
  grep -q '"type":"disconnect"' "$WG_MONITOR_LOG_DIR/events.jsonl"
}

@test "stays online across ticks when traffic keeps growing" {
  # The realistic idempotency contract for a connected client: with the
  # forced PersistentKeepalive=25, rx grows on every 30s tick (~96 bytes
  # per keepalive packet). No transitions should be emitted.
  now=$(date -u +%s)
  iface=$(printf '%s\t%s\t%s\t%s' '(none)' 'srv_pub_key' '51820' 'off')
  for rx in 1000 1100 1200 1300; do
    peer=$(printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s' \
      'peer1' '(none)' '1.2.3.4:51820' '10.13.13.2/32' "$now" "$rx" '2048' '25')
    export MOCK_WG_DUMP="$(build_dump "$iface" "$peer")"
    run_monitor
  done
  if [ -f "$WG_MONITOR_LOG_DIR/events.jsonl" ]; then
    [ ! -s "$WG_MONITOR_LOG_DIR/events.jsonl" ]
  fi
  grep -q '"online":true' "$WG_MONITOR_STATE_DIR/peers-state.json"
}

@test "trims events older than 7 days" {
  mkdir -p "$WG_MONITOR_LOG_DIR" "$WG_MONITOR_STATE_DIR"
  printf '{"serverTimestamp":"2020-01-01T00:00:00Z","publicKey":"old","type":"connect","rx":0,"tx":0,"latestHandshake":0}\n' \
    >"$WG_MONITOR_LOG_DIR/events.jsonl"
  recent=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  printf '{"serverTimestamp":"%s","publicKey":"new","type":"connect","rx":0,"tx":0,"latestHandshake":0}\n' \
    "$recent" >>"$WG_MONITOR_LOG_DIR/events.jsonl"
  unset MOCK_WG_DUMP
  export MOCK_WG_DUMP=''
  run_monitor
  [ "$status" -eq 0 ]
  ! grep -q '"publicKey":"old"' "$WG_MONITOR_LOG_DIR/events.jsonl"
  grep -q '"publicKey":"new"' "$WG_MONITOR_LOG_DIR/events.jsonl"
}

@test "does not leak the peer endpoint into the snapshot when wg reports (none)" {
  now=$(date -u +%s)
  iface=$(printf '%s\t%s\t%s\t%s' '(none)' 'srv_pub_key' '51820' 'off')
  peer=$(printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s' \
    'peer1' '(none)' '(none)' '10.13.13.2/32' "$now" '0' '0' '25')
  export MOCK_WG_DUMP="$(build_dump "$iface" "$peer")"
  run_monitor
  grep -q '"endpoint":null' "$WG_MONITOR_STATE_DIR/peers-state.json"
}
