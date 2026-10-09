# Tests for reopen_ssh.sh (sshd hardening reversal, anti-lockout).
# shellcheck shell=bats

setup() {
  load test_helper
  BIN_DIR="$BATS_TEST_TMPDIR/bin"
  export MOCK_LOG="$BATS_TEST_TMPDIR/mock.log"
  : >"$MOCK_LOG"
  install_mocks "$BIN_DIR"
  export WG_ROOT="$BATS_TEST_TMPDIR/root"
  mkdir -p "$WG_ROOT/etc/ssh"
  CONFIG="$WG_ROOT/etc/ssh/sshd_config"
}

@test "restores prior values from the oldest FAV backup" {
  # Hardened current config.
  printf 'PermitRootLogin no\nPasswordAuthentication no\n' >"$CONFIG"
  # Pre-FAV original, captured in a FAV backup.
  printf 'PermitRootLogin yes\nPasswordAuthentication yes\n' \
    >"${CONFIG}.wg-installer.bak.20260101000000"

  run bash "$SCRIPTS_DIR/reopen_ssh.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *WG-RVT-OK* ]]
  grep -qE '^PermitRootLogin yes' "$CONFIG"
  grep -qE '^PasswordAuthentication yes' "$CONFIG"
}

@test "falls back to safe defaults when no backup exists" {
  printf 'PermitRootLogin no\nPasswordAuthentication no\n' >"$CONFIG"

  run bash "$SCRIPTS_DIR/reopen_ssh.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *WG-RVT-OK* ]]
  grep -qE '^PasswordAuthentication yes' "$CONFIG"
  grep -qE '^PermitRootLogin prohibit-password' "$CONFIG"
}

@test "aborts and leaves config unchanged when sshd -t fails" {
  printf 'PermitRootLogin no\nPasswordAuthentication no\n' >"$CONFIG"
  export MOCK_FAIL='sshd'

  run bash "$SCRIPTS_DIR/reopen_ssh.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *WG-RVT-ABORTED* ]]
  grep -qE '^PermitRootLogin no' "$CONFIG"
  grep -qE '^PasswordAuthentication no' "$CONFIG"
}

@test "normalizes a without-password backup to prohibit-password" {
  # sshd -T reports only the canonical vocabulary; restoring the deprecated
  # alias verbatim made the effective re-check reject its own re-open and
  # roll back to the hardened state (verify-pass MEDIUM-1).
  printf 'PermitRootLogin no\nPasswordAuthentication no\n' >"$CONFIG"
  printf 'PermitRootLogin without-password\nPasswordAuthentication yes\n' \
    >"${CONFIG}.wg-installer.bak.20260101000000"

  run bash "$SCRIPTS_DIR/reopen_ssh.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *WG-RVT-OK* ]]
  grep -qE '^PermitRootLogin prohibit-password' "$CONFIG"
}

@test "accepts Debian 12 reporting without-password for prohibit-password" {
  printf 'PermitRootLogin no\nPasswordAuthentication no\n' >"$CONFIG"
  export MOCK_SSHD_T_PR_OVERRIDE='without-password'

  run bash "$SCRIPTS_DIR/reopen_ssh.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *WG-RVT-OK* ]]
  grep -qE '^PermitRootLogin prohibit-password' "$CONFIG"
}

@test "treats an uppercase hardened No as unusable and re-opens with yes" {
  # `No` must count as the hardened value (case-insensitively) so the safe
  # re-opening default kicks in — re-applying `No` would print WG-RVT-OK
  # over a config that still blocks passwords (verify-pass LOW-1).
  printf 'PermitRootLogin no\nPasswordAuthentication no\n' >"$CONFIG"
  printf 'PermitRootLogin yes\nPasswordAuthentication No\n' \
    >"${CONFIG}.wg-installer.bak.20260101000000"

  run bash "$SCRIPTS_DIR/reopen_ssh.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *WG-RVT-OK* ]]
  grep -qE '^PasswordAuthentication yes' "$CONFIG"
}

@test "rolls back when the effective config still blocks passwords" {
  # Parity with the disable scripts (teardown follow-up): a drop-in can
  # override the rewritten main file, and a WG-RVT-OK claiming an access
  # path that does not exist would let the app remove the FAV key and lock
  # the user out. Simulated by forcing what `sshd -T` reports.
  printf 'PermitRootLogin no\nPasswordAuthentication no\n' >"$CONFIG"
  printf 'PermitRootLogin yes\nPasswordAuthentication yes\n' \
    >"${CONFIG}.wg-installer.bak.20260101000000"
  export MOCK_SSHD_T_PA_OVERRIDE='no'

  run bash "$SCRIPTS_DIR/reopen_ssh.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *WG-RVT-ABORTED* ]]
  # Config must be rolled back to the pre-run hardened state.
  grep -qE '^PermitRootLogin no' "$CONFIG"
  grep -qE '^PasswordAuthentication no' "$CONFIG"
}

@test "aborts when sshd_config is missing" {
  run bash "$SCRIPTS_DIR/reopen_ssh.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *WG-RVT-ABORTED* ]]
}

@test "rolls back and aborts when the sshd reload fails" {
  # Hardened current config with a backup so the script has values to restore.
  printf 'PermitRootLogin no\nPasswordAuthentication no\n' >"$CONFIG"
  printf 'PermitRootLogin yes\nPasswordAuthentication yes\n' \
    >"${CONFIG}.wg-installer.bak.20260101000000"
  # MOCK_FAIL='systemctl' makes every `systemctl` call exit non-zero, which
  # fails `reload_sshd` while leaving `sshd -t` (a separate mock) unaffected.
  export MOCK_FAIL='systemctl'

  run bash "$SCRIPTS_DIR/reopen_ssh.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *WG-RVT-ABORTED* ]]
  # Config must be rolled back to the pre-run hardened state.
  grep -qE '^PermitRootLogin no' "$CONFIG"
  grep -qE '^PasswordAuthentication no' "$CONFIG"
}

@test "rolls back and aborts when sshd is not active after reload" {
  # Hardened current config with a backup so the script has values to restore.
  printf 'PermitRootLogin no\nPasswordAuthentication no\n' >"$CONFIG"
  printf 'PermitRootLogin yes\nPasswordAuthentication yes\n' \
    >"${CONFIG}.wg-installer.bak.20260101000000"
  # MOCK_SSHD_INACTIVE='1' makes `systemctl is-active` exit 1 while
  # `systemctl reload` still succeeds, exercising the post-reload activity check.
  export MOCK_SSHD_INACTIVE='1'

  run bash "$SCRIPTS_DIR/reopen_ssh.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *WG-RVT-ABORTED* ]]
  # Config must be rolled back to the pre-run hardened state.
  grep -qE '^PermitRootLogin no' "$CONFIG"
  grep -qE '^PasswordAuthentication no' "$CONFIG"
}
