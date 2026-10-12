#!/usr/bin/env bats
# Tests for disable_password_auth.sh — the hardening script that disables
# SSH password authentication (spec §10.3). System commands are mocked;
# sshd_config is sandboxed.

load test_helper

setup() {
  REAL_SSHD=$(command -v sshd || true)
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

@test "disable_password_auth.sh catches conditional Include override ignored by real sshd -T" {
  [[ -n $REAL_SSHD ]] || skip 'real sshd unavailable'
  command -v ssh-keygen >/dev/null || skip 'ssh-keygen unavailable'
  ssh-keygen -q -t ed25519 -N '' -f "$BATS_TEST_TMPDIR/hostkey"
  printf 'Match User root Address 192.0.2.0/24\n KbdInteractiveAuthentication yes\n' >"$BATS_TEST_TMPDIR/conditional.conf"
  printf 'HostKey %s/hostkey\nPermitRootLogin no\nPasswordAuthentication no\nKbdInteractiveAuthentication no\nInclude %s/conditional.conf\n' "$BATS_TEST_TMPDIR" "$BATS_TEST_TMPDIR" >"$WG_ROOT/etc/ssh/sshd_config"
  run "$REAL_SSHD" -T -f "$WG_ROOT/etc/ssh/sshd_config"
  [ "$status" -eq 0 ]
  [[ "$output" == *'permitrootlogin no'* ]]
  [[ "$output" == *'kbdinteractiveauthentication no'* ]]
  run "$REAL_SSHD" -T -f "$WG_ROOT/etc/ssh/sshd_config" -C user=root,addr=192.0.2.10,host=example.test
  [ "$status" -eq 0 ]
  [[ "$output" == *'kbdinteractiveauthentication yes'* ]]
  cp "$WG_ROOT/etc/ssh/sshd_config" "$BATS_TEST_TMPDIR/original"
  run bash "$SCRIPTS_DIR/disable_password_auth.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *WG-HRD-ABORTED* ]]
  cmp "$BATS_TEST_TMPDIR/original" "$WG_ROOT/etc/ssh/sshd_config"
  run mock_called systemctl
  [ "$status" -ne 0 ]
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
  printf 'Include %s/etc/ssh/sshd_config.d/*.conf\n' "$WG_ROOT" >>"$WG_ROOT/etc/ssh/sshd_config"
  printf 'PasswordAuthentication yes\n' \
    >"$WG_ROOT/etc/ssh/sshd_config.d/50-cloud-init.conf"
  run bash "$SCRIPTS_DIR/disable_password_auth.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *WG-HRD-ABORTED* ]]
}

@test "disable_password_auth rejects nested nonstandard Includes and all Match password paths" {
  mkdir -p "$WG_ROOT/etc/ssh/custom"
  printf 'Include custom/outer.conf\n' >>"$WG_ROOT/etc/ssh/sshd_config"
  printf 'mAtCh Address 192.0.2.0/24\n iNcLuDe custom/inner*.conf\n' >"$WG_ROOT/etc/ssh/custom/outer.conf"
  for directive in 'pAsSwOrDaUtHeNtIcAtIoN = yes' 'kBdInTeRaCtIvEaUtHeNtIcAtIoN yes' 'ChallengeResponseAuthentication yes'; do
    printf 'Match User only-this-user\n %s\n' "$directive" >"$WG_ROOT/etc/ssh/custom/inner.conf"
    cp "$WG_ROOT/etc/ssh/sshd_config" "$BATS_TEST_TMPDIR/original"
    run bash "$SCRIPTS_DIR/disable_password_auth.sh"
    [ "$status" -ne 0 ]
    [[ "$output" == *WG-HRD-ABORTED* ]]
    cmp "$BATS_TEST_TMPDIR/original" "$WG_ROOT/etc/ssh/sshd_config"
    run mock_called systemctl
    [ "$status" -ne 0 ]
  done
}

@test "disable_password_auth accepts safe nested Includes and prepends globals before included Match" {
  mkdir -p "$WG_ROOT/etc/ssh/custom"
  printf 'Include custom/outer.conf custom/missing*.conf # safe comment\n' >>"$WG_ROOT/etc/ssh/sshd_config"
  printf 'Include custom/inner.conf\nMatch User deploy\n AllowTcpForwarding yes\n' >"$WG_ROOT/etc/ssh/custom/outer.conf"
  printf 'Match Address 192.0.2.0/24\n PasswordAuthentication no\n KbdInteractiveAuthentication no\n ChallengeResponseAuthentication no\n' >"$WG_ROOT/etc/ssh/custom/inner.conf"
  run bash "$SCRIPTS_DIR/disable_password_auth.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *WG-HRD-OK* ]]
  [ "$(head -1 "$WG_ROOT/etc/ssh/sshd_config")" = 'ChallengeResponseAuthentication no' ]
}

@test "disable_password_auth rejects ambiguous Include syntax and recursive Includes" {
  mkdir -p "$WG_ROOT/etc/ssh/custom"
  for directive in 'Include "custom/unsafe.conf"' "Include 'custom/unsafe.conf'" 'Include custom/unsafe#file.conf' '"Include" custom/unsafe.conf' 'Include custom/loop.conf'; do
    printf 'PasswordAuthentication yes\n%s\n' "$directive" >"$WG_ROOT/etc/ssh/sshd_config"
    printf 'Include custom/loop.conf\n' >"$WG_ROOT/etc/ssh/custom/loop.conf"
    run bash "$SCRIPTS_DIR/disable_password_auth.sh"
    [ "$status" -ne 0 ]
    [[ "$output" == *WG-HRD-ABORTED* ]]
    run mock_called systemctl
    [ "$status" -ne 0 ]
  done
}
