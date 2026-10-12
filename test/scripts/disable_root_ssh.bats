#!/usr/bin/env bats
# Tests for disable_root_ssh.sh — the anti-lockout root-SSH-disable script
# (spec §10.2). System commands are mocked; sshd_config is sandboxed.

load test_helper

setup() {
  REAL_SSHD=$(command -v sshd || true)
  install_mocks "$BATS_TEST_TMPDIR/bin"
  export PATH
  export MOCK_LOG="$BATS_TEST_TMPDIR/mock.log"
  : >"$MOCK_LOG"
  export WG_ROOT="$BATS_TEST_TMPDIR/root"
  mkdir -p "$WG_ROOT/etc/ssh"
  printf 'PermitRootLogin yes\n' >"$WG_ROOT/etc/ssh/sshd_config"
}

@test "disable_root_ssh.sh catches conditional Include override ignored by real sshd -T" {
  [[ -n $REAL_SSHD ]] || skip 'real sshd unavailable'
  command -v ssh-keygen >/dev/null || skip 'ssh-keygen unavailable'
  ssh-keygen -q -t ed25519 -N '' -f "$BATS_TEST_TMPDIR/hostkey"
  printf 'Match User root Address 192.0.2.0/24\n PermitRootLogin prohibit-password\n' >"$BATS_TEST_TMPDIR/conditional.conf"
  printf 'HostKey %s/hostkey\nPermitRootLogin no\nPasswordAuthentication no\nKbdInteractiveAuthentication no\nInclude %s/conditional.conf\n' "$BATS_TEST_TMPDIR" "$BATS_TEST_TMPDIR" >"$WG_ROOT/etc/ssh/sshd_config"
  run "$REAL_SSHD" -T -f "$WG_ROOT/etc/ssh/sshd_config"
  [ "$status" -eq 0 ]
  [[ "$output" == *'permitrootlogin no'* ]]
  [[ "$output" == *'kbdinteractiveauthentication no'* ]]
  run "$REAL_SSHD" -T -f "$WG_ROOT/etc/ssh/sshd_config" -C user=root,addr=192.0.2.10,host=example.test
  [ "$status" -eq 0 ]
  # OpenSSH versions serialize this equivalent setting under either name.
  [[ "$output" == *'permitrootlogin prohibit-password'* ||
     "$output" == *'permitrootlogin without-password'* ]]
  cp "$WG_ROOT/etc/ssh/sshd_config" "$BATS_TEST_TMPDIR/original"
  run bash "$SCRIPTS_DIR/disable_root_ssh.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *WG-LCK-ABORTED* ]]
  cmp "$BATS_TEST_TMPDIR/original" "$WG_ROOT/etc/ssh/sshd_config"
  run mock_called systemctl
  [ "$status" -ne 0 ]
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
  run grep -qE '^[[:space:]]+PermitRootLogin[[:space:]]+yes' \
    "$WG_ROOT/etc/ssh/sshd_config"
  [ "$status" -ne 0 ]
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
  printf 'Include %s/etc/ssh/sshd_config.d/*.conf\n' "$WG_ROOT" >>"$WG_ROOT/etc/ssh/sshd_config"
  printf 'PermitRootLogin yes\n' \
    >"$WG_ROOT/etc/ssh/sshd_config.d/99-cloud-init.conf"
  run bash "$SCRIPTS_DIR/disable_root_ssh.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *WG-LCK-ABORTED* ]]
}

@test "disable_root_ssh aborts on a prohibit-password drop-in" {
  mkdir -p "$WG_ROOT/etc/ssh/sshd_config.d"
  printf 'Include %s/etc/ssh/sshd_config.d/*.conf\n' "$WG_ROOT" >>"$WG_ROOT/etc/ssh/sshd_config"
  printf 'PermitRootLogin prohibit-password\n' \
    >"$WG_ROOT/etc/ssh/sshd_config.d/60-cloudimg.conf"
  run bash "$SCRIPTS_DIR/disable_root_ssh.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *WG-LCK-ABORTED* ]]
}

@test "disable_root_ssh rejects every permissive value in nested nonstandard Include Match rules" {
  mkdir -p "$WG_ROOT/etc/ssh/custom"
  printf 'Include custom/outer.conf\n' >>"$WG_ROOT/etc/ssh/sshd_config"
  printf 'mAtCh Address 192.0.2.0/24\n iNcLuDe custom/inner*.conf\n' >"$WG_ROOT/etc/ssh/custom/outer.conf"
  for value in yes prohibit-password without-password forced-commands-only; do
    printf 'Match User root\n pErMiTrOoTlOgIn = %s\n' "$value" >"$WG_ROOT/etc/ssh/custom/inner.conf"
    cp "$WG_ROOT/etc/ssh/sshd_config" "$BATS_TEST_TMPDIR/original"
    run bash "$SCRIPTS_DIR/disable_root_ssh.sh"
    [ "$status" -ne 0 ]
    [[ "$output" == *WG-LCK-ABORTED* ]]
    cmp "$BATS_TEST_TMPDIR/original" "$WG_ROOT/etc/ssh/sshd_config"
    run mock_called systemctl
    [ "$status" -ne 0 ]
  done
}

@test "disable_root_ssh accepts safe nested Includes and prepends global before included Match" {
  mkdir -p "$WG_ROOT/etc/ssh/custom"
  printf 'Include custom/outer.conf custom/missing*.conf\n' >>"$WG_ROOT/etc/ssh/sshd_config"
  printf 'Include custom/inner.conf\nMatch User deploy\n AllowTcpForwarding yes\n' >"$WG_ROOT/etc/ssh/custom/outer.conf"
  printf 'Match Address 192.0.2.0/24\n PermitRootLogin no\n' >"$WG_ROOT/etc/ssh/custom/inner.conf"
  run bash "$SCRIPTS_DIR/disable_root_ssh.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *WG-LCK-OK* ]]
  [ "$(head -1 "$WG_ROOT/etc/ssh/sshd_config")" = 'PermitRootLogin no' ]
}

@test "disable_root_ssh rejects ambiguous Include syntax and recursive Includes" {
  mkdir -p "$WG_ROOT/etc/ssh/custom"
  for directive in 'Include "custom/unsafe.conf"' "Include 'custom/unsafe.conf'" 'Include custom/unsafe#file.conf' '"Include" custom/unsafe.conf' 'Include custom/loop.conf'; do
    printf 'PermitRootLogin yes\n%s\n' "$directive" >"$WG_ROOT/etc/ssh/sshd_config"
    printf 'Include custom/loop.conf\n' >"$WG_ROOT/etc/ssh/custom/loop.conf"
    run bash "$SCRIPTS_DIR/disable_root_ssh.sh"
    [ "$status" -ne 0 ]
    [[ "$output" == *WG-LCK-ABORTED* ]]
    run mock_called systemctl
    [ "$status" -ne 0 ]
  done
}
