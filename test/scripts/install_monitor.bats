#!/usr/bin/env bats
# Tests for install_monitor.sh (the peer-monitor installer).

load test_helper

setup() {
  install_mocks "$BATS_TEST_TMPDIR/bin"
  export PATH
  export MOCK_LOG="$BATS_TEST_TMPDIR/mock.log"
  : >"$MOCK_LOG"
  export WG_ROOT="$BATS_TEST_TMPDIR/root"
  export WG_MONITOR_BIN="$WG_ROOT/usr/local/bin/wg-monitor.sh"
  export WG_MONITOR_SYSTEMD_DIR="$WG_ROOT/etc/systemd/system"
  export WG_MONITOR_LOGROTATE="$WG_ROOT/etc/logrotate.d/fav"
  export WG_MONITOR_ENV="$WG_ROOT/etc/fav/monitor.env"
  export WG_MONITOR_SKIP_SYSTEMD='true'
  export NEW_USERNAME='deploy'
  INSTALL_MONITOR="$SCRIPTS_DIR/install_monitor.sh"
}

@test "install_monitor installs the units and writes monitor.env" {
  export WG_INTERFACE='wg0'
  run bash "$INSTALL_MONITOR"
  [ "$status" -eq 0 ]
  [ -f "$WG_MONITOR_BIN" ]
  [ -f "$WG_MONITOR_SYSTEMD_DIR/wg-monitor.service" ]
  [ -f "$WG_MONITOR_SYSTEMD_DIR/wg-monitor.timer" ]
  grep -q 'WG_INTERFACE="wg0"' "$WG_MONITOR_ENV"
  grep -q 'NEW_USERNAME="deploy"' "$WG_MONITOR_ENV"
}

@test "install_monitor templates the logrotate create owner to the user" {
  # logrotate's `create` replaces the per-tick chown the monitor applies:
  # a root:root events.jsonl is unreadable to the key-authenticated login
  # user the app polls as (verify-pass LOW-2).
  run bash "$INSTALL_MONITOR"
  [ "$status" -eq 0 ]
  grep -q 'create 0640 root deploy' "$WG_MONITOR_LOGROTATE"
}

@test "install_monitor substitutes the interface into the service unit" {
  # A non-wg0 interface must be wired into After=/Wants= (audit M-monitor-iface).
  export WG_INTERFACE='wg1'
  run bash "$INSTALL_MONITOR"
  [ "$status" -eq 0 ]
  grep -q 'wg-quick@wg1.service' "$WG_MONITOR_SYSTEMD_DIR/wg-monitor.service"
  ! grep -q 'wg-quick@wg0' "$WG_MONITOR_SYSTEMD_DIR/wg-monitor.service"
}

@test "install_monitor rejects an invalid interface name" {
  export WG_INTERFACE='bad name!'
  run bash "$INSTALL_MONITOR"
  [ "$status" -ne 0 ]
}

@test "install_monitor rejects an invalid username" {
  export WG_INTERFACE='wg0'
  export NEW_USERNAME='Bad Name'
  run bash "$INSTALL_MONITOR"
  [ "$status" -ne 0 ]
}
