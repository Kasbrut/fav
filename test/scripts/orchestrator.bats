#!/usr/bin/env bats
# End-to-end tests for install_wireguard.sh (spec §8.3): the orchestrator runs
# every module against the mock harness in a sandboxed run directory.

load test_helper

setup() {
  install_mocks "$BATS_TEST_TMPDIR/bin"
  export PATH
  export MOCK_LOG="$BATS_TEST_TMPDIR/mock.log"
  : >"$MOCK_LOG"
  export MOCK_KERNEL='6.1.0'

  # Mirror what the app uploads to /opt/wg-installer/<run-id>/ on the server.
  RUN_DIR="$BATS_TEST_TMPDIR/run-bats-001"
  cp -R "$SCRIPTS_DIR" "$RUN_DIR"

  printf 'ID=debian\nVERSION_ID=12\n' >"$BATS_TEST_TMPDIR/os-release"
  export OS_RELEASE_FILE="$BATS_TEST_TMPDIR/os-release"
  export WG_ROOT="$BATS_TEST_TMPDIR/root"
  export WG_STATE_DIR="$BATS_TEST_TMPDIR/state"
  export WG_LOG_DIR="$BATS_TEST_TMPDIR/log"
  export FAV_PROC_ROOT="$BATS_TEST_TMPDIR/proc"
  mkdir -p "$FAV_PROC_ROOT/sys/net/ipv6/conf/all"
  printf '0\n' >"$FAV_PROC_ROOT/sys/net/ipv6/conf/all/disable_ipv6"
  # Mirror the complete v2 transport emitted by ConfigEnvWriter. Individual
  # tests can still override fields through config.env or the environment.
  export FAV_CONFIG_VERSION=2
  export FAV_INSTALLATION_ID='install-1'
  export FAV_OPERATION_ID='operation-1'
  export VPN_SUBNET='10.13.13.0/24'
  export VPN_IPV6_ULA_SUBNET='fd12:3456:789a::/64'
  export VPN_IPV6_ROUTED_SUBNET=''
  export IPV6_PROBE_TARGET=''
  export PUBLIC_ENDPOINT='203.0.113.10'
  export WG_PORT=51820
  export SSH_PORT=22
  export DNS='1.1.1.1, 1.0.0.1'
  export MTU=1420
  STATE_FILE="$WG_STATE_DIR/run-bats-001.state"
  EXIT_FILE="$WG_STATE_DIR/run-bats-001.exit"
}

@test "orchestrator completes every step and reports success" {
  run bash "$RUN_DIR/install_wireguard.sh"
  [ "$status" -eq 0 ]
  [ "$(cat "$EXIT_FILE")" = '0' ]
  grep -q '"probe": {"status": "done"' "$STATE_FILE"
  grep -q '"install_pkgs": {"status": "done"' "$STATE_FILE"
  grep -q '"generate_keys": {"status": "done"' "$STATE_FILE"
  grep -q '"finalize": {"status": "done"' "$STATE_FILE"
  grep -q '"create_user": {"status": "skipped"' "$STATE_FILE"
  grep -q '"deploy_app_key": {"status": "skipped"' "$STATE_FILE"
  grep -q '"hardening": {"status": "skipped"' "$STATE_FILE"
  grep -q '"error": null' "$STATE_FILE"
}

@test "orchestrator runs deploy_app_key when SSH_PUBKEY is provided" {
  cat >"$RUN_DIR/config.env" <<'EOF'
SSH_PUBKEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBcDeFGhIjKlMnOpQrSt fav@dev"
EOF
  run bash "$RUN_DIR/install_wireguard.sh"
  [ "$status" -eq 0 ]
  grep -q '"deploy_app_key": {"status": "done"' "$STATE_FILE"
  # Default target when CREATE_USER is not set is root — sandboxed under
  # $WG_ROOT/home/root by the mocked `getent`.
  [ -f "$WG_ROOT/home/root/.ssh/authorized_keys" ]
}

@test "orchestrator records the failing step and a non-zero exit" {
  printf 'NEW_PASSWORD="sup3rs3cretpw"\n' >"$RUN_DIR/config.env"
  export MOCK_FAIL='apt-get'
  run bash "$RUN_DIR/install_wireguard.sh"
  [ "$status" -ne 0 ]
  [ "$(cat "$EXIT_FILE")" != '0' ]
  grep -q '"probe": {"status": "done"' "$STATE_FILE"
  grep -q '"install_pkgs": {"status": "error"' "$STATE_FILE"
  # The error channel must not leak the password into the state file.
  run grep -rl 'sup3rs3cretpw' "$WG_STATE_DIR"
  [ "$status" -ne 0 ]
}

@test "orchestrator rejects a malformed INTERFACE_NAME (path traversal)" {
  # Defense-in-depth: the app validates first, but a bad interface name must
  # never reach a path/unit name server-side (audit M-script-validate).
  printf 'INTERFACE_NAME="../../etc/x"\n' >"$RUN_DIR/config.env"
  run bash "$RUN_DIR/install_wireguard.sh"
  [ "$status" -ne 0 ]
}

@test "orchestrator rejects an out-of-range WG_PORT" {
  printf 'WG_PORT="99999"\n' >"$RUN_DIR/config.env"
  run bash "$RUN_DIR/install_wireguard.sh"
  [ "$status" -ne 0 ]
}

@test "orchestrator rejects a malformed VPN_SUBNET" {
  printf 'VPN_SUBNET="not-a-subnet"\n' >"$RUN_DIR/config.env"
  run bash "$RUN_DIR/install_wireguard.sh"
  [ "$status" -ne 0 ]
}

@test "orchestrator wipes config.env even if an early step fails" {
  # config.env holds the cleartext login password. A failure before the normal
  # removal (here, a corrupt config.env whose sourcing aborts under set -e)
  # must still leave no config.env on disk (audit H6).
  printf 'NEW_PASSWORD="sup3rs3cretpw"\nfalse\n' >"$RUN_DIR/config.env"
  run bash "$RUN_DIR/install_wireguard.sh"
  [ "$status" -ne 0 ]
  [ ! -e "$RUN_DIR/config.env" ]
}

@test "orchestrator refuses to start when another run holds the lock" {
  # Cross-run flock (audit M-no-lock): overlapping installers against one
  # host would interleave writes to the same config. The mock's flock is a
  # no-op; MOCK_FAIL exercises the refusal branch.
  export MOCK_FAIL='flock'
  run bash "$RUN_DIR/install_wireguard.sh"
  [ "$status" -ne 0 ]
  [ "$(cat "$EXIT_FILE")" != '0' ]
  grep -q '"probe": {"status": "pending"' "$STATE_FILE"
  # The refusal reason reaches the state file, not only the run log —
  # otherwise the app shows a generic step failure (verify-pass LOW-7).
  grep -q '"error": "another installer run is active"' "$STATE_FILE"
}

@test "orchestrator fails fast when a module has a syntax error" {
  # The modules are user-editable in the app: a syntactically broken module
  # must abort the run at launch, before any module executes, instead of
  # failing mid-install with a partially provisioned server.
  printf 'if true; then\n' >>"$RUN_DIR/modules/40_write_server_conf.sh"
  run bash "$RUN_DIR/install_wireguard.sh"
  [ "$status" -ne 0 ]
  [ "$(cat "$EXIT_FILE")" != '0' ]
  grep -q '"write_server_conf": {"status": "error"' "$STATE_FILE"
  grep -q 'module 40_write_server_conf.sh failed syntax validation' \
    "$STATE_FILE"
  # Fail-fast means not even the first module ran.
  grep -q '"probe": {"status": "pending"' "$STATE_FILE"
  run mock_called apt-get
  [ "$status" -ne 0 ]
}

@test "orchestrator runs create_user when config.env enables it" {
  mkdir -p "$WG_ROOT/etc/ssh"
  printf 'PermitRootLogin yes\n' >"$WG_ROOT/etc/ssh/sshd_config"
  cat >"$RUN_DIR/config.env" <<'EOF'
CREATE_USER="true"
NEW_USERNAME="deploy"
NEW_PASSWORD="pw"
SSH_PUBKEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBcDeFGhIjKlMnOpQrSt fav@dev"
EOF
  run bash "$RUN_DIR/install_wireguard.sh"
  [ "$status" -eq 0 ]
  grep -q '"create_user": {"status": "done"' "$STATE_FILE"
  grep -q '"deploy_app_key": {"status": "done"' "$STATE_FILE"
  mock_called useradd
  # The Ed25519 key landed in the new user's home, not in root's.
  [ -f "$WG_ROOT/home/deploy/.ssh/authorized_keys" ]
}

@test "orchestrator keeps secrets out of the state file and logs" {
  mkdir -p "$WG_ROOT/etc/ssh"
  printf 'PermitRootLogin yes\n' >"$WG_ROOT/etc/ssh/sshd_config"
  cat >"$RUN_DIR/config.env" <<'EOF'
CREATE_USER="true"
NEW_USERNAME="deploy"
NEW_PASSWORD="sup3rs3cretpw"
EOF
  run bash "$RUN_DIR/install_wireguard.sh"
  [ "$status" -eq 0 ]
  [[ "$output" != *sup3rs3cretpw* ]]
  run grep -rl 'sup3rs3cretpw' "$WG_STATE_DIR"
  [ "$status" -ne 0 ]
}
