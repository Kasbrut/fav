#!/usr/bin/env bats
# Tests for disable_root_ssh.sh — the anti-lockout root-SSH-disable script
# (spec §10.2). System commands are mocked; sshd_config is sandboxed.

load test_helper

setup() {
  install_mocks "$BATS_TEST_TMPDIR/bin"
  export PATH
  export MOCK_LOG="$BATS_TEST_TMPDIR/mock.log"
  : >"$MOCK_LOG"
  export WG_ROOT="$BATS_TEST_TMPDIR/root"
  mkdir -p "$WG_ROOT/etc/ssh"
  printf 'PermitRootLogin yes\n' >"$WG_ROOT/etc/ssh/sshd_config"
}

@test "disable_root_ssh disables root login and reports WG-LCK-OK" {
  run bash "$SCRIPTS_DIR/disable_root_ssh.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *WG-LCK-OK* ]]
  grep -q '^PermitRootLogin no' "$WG_ROOT/etc/ssh/sshd_config"
}

@test "disable_root_ssh keeps PermitRootLogin global when config ends with a Match block" {
  cat >"$WG_ROOT/etc/ssh/sshd_config" <<EOF
PermitRootLogin yes
Match Address 10.0.0.0/8
    AllowTcpForwarding yes
EOF
  run bash "$SCRIPTS_DIR/disable_root_ssh.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *WG-LCK-OK* ]]
  # The directive must land BEFORE the Match line (global scope); appending it
  # after Match would scope it to the block and leave root login enabled.
  prl_line=$(grep -n '^PermitRootLogin no' \
    "$WG_ROOT/etc/ssh/sshd_config" | head -1 | cut -d: -f1)
  match_line=$(grep -n '^Match ' "$WG_ROOT/etc/ssh/sshd_config" | cut -d: -f1)
  [ -n "$prl_line" ]
  [ "$prl_line" -lt "$match_line" ]
}

@test "disable_root_ssh disables an indented PermitRootLogin directive" {
  printf '    PermitRootLogin yes\n' >"$WG_ROOT/etc/ssh/sshd_config"
  run bash "$SCRIPTS_DIR/disable_root_ssh.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *WG-LCK-OK* ]]
  # The indented `yes` must be gone, replaced by a global `no`.
  ! grep -qE '^[[:space:]]+PermitRootLogin[[:space:]]+yes' \
    "$WG_ROOT/etc/ssh/sshd_config"
  grep -qx 'PermitRootLogin no' "$WG_ROOT/etc/ssh/sshd_config"
}

@test "disable_root_ssh aborts and keeps root login when sshd -t fails" {
  export MOCK_FAIL='sshd'
  run bash "$SCRIPTS_DIR/disable_root_ssh.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *WG-LCK-ABORTED* ]]
  grep -q '^PermitRootLogin yes' "$WG_ROOT/etc/ssh/sshd_config"
}

@test "disable_root_ssh rolls back when sshd is inactive after reload" {
  export MOCK_SSHD_INACTIVE='1'
  run bash "$SCRIPTS_DIR/disable_root_ssh.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *WG-LCK-ABORTED* ]]
  grep -q '^PermitRootLogin yes' "$WG_ROOT/etc/ssh/sshd_config"
}

@test "disable_root_ssh aborts when a drop-in still permits root login" {
  mkdir -p "$WG_ROOT/etc/ssh/sshd_config.d"
  printf 'PermitRootLogin yes\n' \
    >"$WG_ROOT/etc/ssh/sshd_config.d/99-cloud-init.conf"
  run bash "$SCRIPTS_DIR/disable_root_ssh.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *WG-LCK-ABORTED* ]]
}

@test "disable_root_ssh aborts on a prohibit-password drop-in" {
  mkdir -p "$WG_ROOT/etc/ssh/sshd_config.d"
  printf 'PermitRootLogin prohibit-password\n' \
    >"$WG_ROOT/etc/ssh/sshd_config.d/60-cloudimg.conf"
  run bash "$SCRIPTS_DIR/disable_root_ssh.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *WG-LCK-ABORTED* ]]
}
