#!/usr/bin/env bats
# Tests for disable_password_auth.sh — the hardening script that disables
# SSH password authentication (spec §10.3). System commands are mocked;
# sshd_config is sandboxed.

load test_helper

setup() {
  install_mocks "$BATS_TEST_TMPDIR/bin"
  export PATH
  export MOCK_LOG="$BATS_TEST_TMPDIR/mock.log"
  : >"$MOCK_LOG"
  export WG_ROOT="$BATS_TEST_TMPDIR/root"
  mkdir -p "$WG_ROOT/etc/ssh"
  cat >"$WG_ROOT/etc/ssh/sshd_config" <<EOF
PermitRootLogin no
PasswordAuthentication yes
EOF
}

@test "disable_password_auth disables password login and reports WG-HRD-OK" {
  run bash "$SCRIPTS_DIR/disable_password_auth.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *WG-HRD-OK* ]]
  grep -qx 'PasswordAuthentication no' "$WG_ROOT/etc/ssh/sshd_config"
  grep -qx 'PubkeyAuthentication yes' "$WG_ROOT/etc/ssh/sshd_config"
  grep -qx 'KbdInteractiveAuthentication no' "$WG_ROOT/etc/ssh/sshd_config"
}

@test "disable_password_auth removes any commented PasswordAuthentication" {
  cat >"$WG_ROOT/etc/ssh/sshd_config" <<EOF
PermitRootLogin no
#PasswordAuthentication yes
# PasswordAuthentication no
PasswordAuthentication yes
EOF
  run bash "$SCRIPTS_DIR/disable_password_auth.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *WG-HRD-OK* ]]
  # Exactly one PasswordAuthentication line, set to no.
  run grep -cE '^[[:space:]]*#?[[:space:]]*PasswordAuthentication' \
    "$WG_ROOT/etc/ssh/sshd_config"
  [ "$output" -eq 1 ]
  grep -qx 'PasswordAuthentication no' "$WG_ROOT/etc/ssh/sshd_config"
}

@test "disable_password_auth aborts when sshd -t fails on the candidate" {
  export MOCK_FAIL='sshd'
  run bash "$SCRIPTS_DIR/disable_password_auth.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *WG-HRD-ABORTED* ]]
  # The original config is untouched.
  grep -qx 'PasswordAuthentication yes' "$WG_ROOT/etc/ssh/sshd_config"
}

@test "disable_password_auth rolls back when sshd is inactive after reload" {
  export MOCK_SSHD_INACTIVE='1'
  run bash "$SCRIPTS_DIR/disable_password_auth.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *WG-HRD-ABORTED* ]]
  # Rolled back to the original config.
  grep -qx 'PasswordAuthentication yes' "$WG_ROOT/etc/ssh/sshd_config"
}

@test "disable_password_auth keeps the directive global when config ends with a Match block" {
  cat >"$WG_ROOT/etc/ssh/sshd_config" <<EOF
PasswordAuthentication yes
Match User deploy
    AllowTcpForwarding yes
EOF
  run bash "$SCRIPTS_DIR/disable_password_auth.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *WG-HRD-OK* ]]
  # The directive must land BEFORE the Match line (global scope); appending it
  # after Match would scope it to the block and leave global auth at its
  # default.
  pa_line=$(grep -n '^PasswordAuthentication no' \
    "$WG_ROOT/etc/ssh/sshd_config" | head -1 | cut -d: -f1)
  match_line=$(grep -n '^Match ' "$WG_ROOT/etc/ssh/sshd_config" | cut -d: -f1)
  [ -n "$pa_line" ]
  [ "$pa_line" -lt "$match_line" ]
}

@test "disable_password_auth aborts when a drop-in re-enables password auth" {
  mkdir -p "$WG_ROOT/etc/ssh/sshd_config.d"
  printf 'PasswordAuthentication yes\n' \
    >"$WG_ROOT/etc/ssh/sshd_config.d/50-cloud-init.conf"
  run bash "$SCRIPTS_DIR/disable_password_auth.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *WG-HRD-ABORTED* ]]
}
