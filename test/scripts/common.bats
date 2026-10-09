#!/usr/bin/env bats
# State-machine tests for lib/common.sh (spec §7.4).

load test_helper

setup() {
  export RUN_ID='run-test'
  export STATE_FILE="$BATS_TEST_TMPDIR/run-test.state"
  export EXIT_FILE="$BATS_TEST_TMPDIR/run-test.exit"
  source "$SCRIPTS_DIR/lib/common.sh"
}

@test "json_escape escapes quotes and backslashes" {
  run json_escape 'a"b\c'
  [ "$status" -eq 0 ]
  [ "$output" = 'a\"b\\c' ]
}

@test "json_escape flattens newlines into spaces" {
  run json_escape "$(printf 'one\ntwo')"
  [ "$output" = 'one two' ]
}

@test "now_iso prints a UTC ISO-8601 timestamp" {
  run now_iso
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]
}

@test "state_init writes every step as pending" {
  state_init
  [ -f "$STATE_FILE" ]
  grep -q '"run_id": "run-test"' "$STATE_FILE"
  grep -q '"current_step": "init"' "$STATE_FILE"
  grep -q '"probe": {"status": "pending"}' "$STATE_FILE"
  grep -q '"finalize": {"status": "pending"}' "$STATE_FILE"
  grep -q '"error": null' "$STATE_FILE"
}

@test "set_step running marks the current step with a start time" {
  state_init
  set_step probe running
  grep -q '"current_step": "probe"' "$STATE_FILE"
  grep -q '"probe": {"status": "running", "started_at": "' "$STATE_FILE"
}

@test "set_step done records both a start and an end time" {
  state_init
  set_step probe running
  set_step probe done
  grep -q '"probe": {"status": "done", "started_at": ".*", "ended_at": ".*"}' \
    "$STATE_FILE"
}

@test "set_step error stores the run error message" {
  state_init
  set_step probe running
  set_step probe error 'something broke'
  grep -q '"probe": {"status": "error"' "$STATE_FILE"
  grep -q '"error": "something broke"' "$STATE_FILE"
}

@test "set_step skipped marks an optional step" {
  state_init
  set_step create_user skipped
  grep -q '"create_user": {"status": "skipped"' "$STATE_FILE"
}

@test "on_installer_exit writes a zero exit code on success" {
  run bash -c '
    source "$1"
    RUN_ID=t
    STATE_FILE="$2/t.state"
    EXIT_FILE="$2/t.exit"
    state_init
    on_installer_exit
  ' _ "$SCRIPTS_DIR/lib/common.sh" "$BATS_TEST_TMPDIR"
  [ "$status" -eq 0 ]
  [ "$(cat "$BATS_TEST_TMPDIR/t.exit")" = '0' ]
}

@test "on_installer_exit flags the running step on a failure" {
  run bash -c '
    source "$1"
    RUN_ID=t
    STATE_FILE="$2/t.state"
    EXIT_FILE="$2/t.exit"
    state_init
    set_step probe running
    false
    on_installer_exit
  ' _ "$SCRIPTS_DIR/lib/common.sh" "$BATS_TEST_TMPDIR"
  [ "$(cat "$BATS_TEST_TMPDIR/t.exit")" = '1' ]
  grep -q '"probe": {"status": "error"' "$BATS_TEST_TMPDIR/t.state"
  grep -q '"error": "step probe failed' "$BATS_TEST_TMPDIR/t.state"
}
