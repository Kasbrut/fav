# Tests for the services teardown orchestrator.
# shellcheck shell=bats

setup() {
  load test_helper
  BIN_DIR="$BATS_TEST_TMPDIR/bin"
  export MOCK_LOG="$BATS_TEST_TMPDIR/mock.log"
  : >"$MOCK_LOG"
  install_mocks "$BIN_DIR"
  export WG_ROOT="$BATS_TEST_TMPDIR/root"
  mkdir -p "$WG_ROOT"

  RUN_DIR="$BATS_TEST_TMPDIR/run-bats-trd"
  cp -R "$SCRIPTS_DIR" "$RUN_DIR"
  export WG_STATE_DIR="$BATS_TEST_TMPDIR/state"
  export WG_LOG_DIR="$BATS_TEST_TMPDIR/log"
  STATE_FILE="$WG_STATE_DIR/run-bats-trd.state"
  EXIT_FILE="$WG_STATE_DIR/run-bats-trd.exit"
}

@test "teardown orchestrator rejects a malformed INTERFACE_NAME" {
  # INTERFACE_NAME is interpolated into rm -f paths by the teardown modules
  # (audit M-script-validate, teardown parity).
  printf 'INTERFACE_NAME="../../etc/x"\n' >"$RUN_DIR/config.env"
  run bash "$RUN_DIR/teardown_wireguard.sh" "$RUN_DIR"
  [ "$status" -ne 0 ]
}

@test "orchestrator runs every teardown step and exits 0 on a clean server" {
  run bash "$RUN_DIR/teardown_wireguard.sh" "$RUN_DIR"
  [ "$status" -eq 0 ]
  [ "$(cat "$EXIT_FILE")" = '0' ]
  # The app keys success off this stdout marker, not the SSH exit code.
  [[ "$output" == *"WG-TRD-OK"* ]]
  grep -q '"stop_service": {"status": "done"' "$STATE_FILE"
  grep -q '"remove_monitor": {"status": "done"' "$STATE_FILE"
  grep -q '"remove_firewall": {"status": "done"' "$STATE_FILE"
  grep -q '"remove_forwarding": {"status": "done"' "$STATE_FILE"
  grep -q '"remove_config": {"status": "done"' "$STATE_FILE"
  grep -q '"remove_fail2ban_jail": {"status": "done"' "$STATE_FILE"
  grep -q '"error": null' "$STATE_FILE"
}
