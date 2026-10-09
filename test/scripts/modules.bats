#!/usr/bin/env bats
# Per-module tests for the installer modules (spec §8.2): one success case and
# one failure mode each, with all system commands mocked.

load test_helper

setup() {
  install_mocks "$BATS_TEST_TMPDIR/bin"
  export PATH
  export MOCK_LOG="$BATS_TEST_TMPDIR/mock.log"
  : >"$MOCK_LOG"
  export WG_ROOT="$BATS_TEST_TMPDIR/root"
  mkdir -p "$WG_ROOT"
  export INTERFACE_NAME='wg0'
}

setup_v2_network_result() {
  local mode=${1:-blocked}
  local prefix='fd12:3456:789a::/64'
  local status='unknown'
  if [[ $mode == routed ]]; then
    prefix='2600:abcd:1234:5678::/64'
    status='supported'
  fi
  export FAV_CONFIG_VERSION=2
  export FAV_INSTALLATION_ID='install-1'
  export FAV_OPERATION_ID='operation-1'
  export VPN_SUBNET='10.13.13.0/24'
  export VPN_IPV6_ULA_SUBNET='fd12:3456:789a::/64'
  export VPN_IPV6_ROUTED_SUBNET=''
  if [[ $mode == routed ]]; then
    export VPN_IPV6_ROUTED_SUBNET="$prefix"
  fi
  export PUBLIC_ENDPOINT='vpn.example.org'
  export WG_PORT=51820
  export SSH_PORT=22
  export DNS='1.1.1.1, 2606:4700:4700::1111'
  export MTU=1420
  export RUN_DIR="$BATS_TEST_TMPDIR/run-$mode"
  mkdir -p "$RUN_DIR/lib"
  cp "$SCRIPTS_DIR/lib/profile_renderer.py" "$RUN_DIR/lib/"
  cat >"$RUN_DIR/network-result.json" <<JSON
{"schemaVersion":2,"installationId":"install-1","operationId":"operation-1","revision":1,"network":{"ipv4Subnet":"10.13.13.0/24","ipv6Mode":"$mode","ipv6Subnet":"$prefix","fallbackIpv6Subnet":"fd12:3456:789a::/64","serverIpv6Address":"${prefix%/64}1/64","wan4":"eth0","wan6":null},"capability":{"status":"$status","reason":"test","checkedAt":"2026-09-17T00:00:00Z"}}
JSON
}

# --- 00_probe --------------------------------------------------------------

@test "00_probe accepts a supported distro and a recent kernel" {
  printf 'ID=debian\nVERSION_ID=12\n' >"$BATS_TEST_TMPDIR/os-release"
  export OS_RELEASE_FILE="$BATS_TEST_TMPDIR/os-release"
  export MOCK_KERNEL='6.1.0'
  run_module modules/00_probe.sh run_probe
  [ "$status" -eq 0 ]
}

@test "00_probe rejects an unsupported distribution" {
  printf 'ID=fedora\nVERSION_ID=40\n' >"$BATS_TEST_TMPDIR/os-release"
  export OS_RELEASE_FILE="$BATS_TEST_TMPDIR/os-release"
  export MOCK_KERNEL='6.1.0'
  run_module modules/00_probe.sh run_probe
  [ "$status" -ne 0 ]
}

@test "00_probe rejects a kernel older than 5.6" {
  printf 'ID=ubuntu\nVERSION_ID=20.04\n' >"$BATS_TEST_TMPDIR/os-release"
  export OS_RELEASE_FILE="$BATS_TEST_TMPDIR/os-release"
  export MOCK_KERNEL='4.19.0'
  run_module modules/00_probe.sh run_probe
  [ "$status" -ne 0 ]
}

# --- 10_install_pkgs -------------------------------------------------------

@test "10_install_pkgs installs the wireguard packages" {
  run_module modules/10_install_pkgs.sh run_install_pkgs
  [ "$status" -eq 0 ]
  mock_called apt-get
}

@test "10_install_pkgs fails when apt-get fails" {
  export MOCK_FAIL='apt-get'
  run_module modules/10_install_pkgs.sh run_install_pkgs
  [ "$status" -ne 0 ]
}

# --- 20_create_user --------------------------------------------------------

@test "20_create_user creates the user and keeps the password off the log" {
  export NEW_USERNAME='deploy'
  export NEW_PASSWORD='s3cret-pw'
  run_module modules/20_create_user.sh run_create_user
  [ "$status" -eq 0 ]
  mock_called useradd
  # The password must never reach the command log.
  run grep -q 's3cret-pw' "$MOCK_LOG"
  [ "$status" -ne 0 ]
}

@test "20_create_user ignores DISABLE_ROOT_SSH (root disable is app-driven)" {
  # The inline root-disable was a weaker stale copy of disable_root_ssh.sh:
  # it could not prove the new login works (spec §10.2 step 3) because the
  # module runs detached. The app never set the flag (ConfigEnvWriter pins
  # it to false); the only root-disable path is the app-driven hardening
  # flow with the full anti-lockout harness (deep-audit low nit).
  mkdir -p "$WG_ROOT/etc/ssh"
  printf 'PermitRootLogin yes\n' >"$WG_ROOT/etc/ssh/sshd_config"
  export NEW_USERNAME='deploy'
  export NEW_PASSWORD='s3cret-pw'
  export DISABLE_ROOT_SSH='true'
  run_module modules/20_create_user.sh run_create_user
  [ "$status" -eq 0 ]
  # The config is completely untouched: no rewrite, no appended directive,
  # no sshd validation call.
  grep -q '^PermitRootLogin yes' "$WG_ROOT/etc/ssh/sshd_config"
  run grep -q 'PermitRootLogin no' "$WG_ROOT/etc/ssh/sshd_config"
  [ "$status" -ne 0 ]
  run mock_called sshd
  [ "$status" -ne 0 ]
}

@test "20_create_user completes password + sudo when the user already exists" {
  # A first run that died between useradd and usermod (or a pre-existing FAV
  # user with no password) must converge on re-run: the 'user exists' path must
  # still set the password and sudo membership (audit H8).
  export NEW_USERNAME='deploy'
  export NEW_PASSWORD='s3cret-pw'
  export MOCK_USER_EXISTS='1'
  run_module modules/20_create_user.sh run_create_user
  [ "$status" -eq 0 ]
  mock_called usermod
  mock_called chpasswd
}

@test "20_create_user does not reset an existing user's usable password" {
  # If the account already has a usable password (an admin's pre-existing
  # user), FAV must not overwrite it; sudo membership is still (idempotently)
  # ensured.
  export NEW_USERNAME='deploy'
  export NEW_PASSWORD='s3cret-pw'
  export MOCK_USER_EXISTS='1'
  export MOCK_PW_STATUS='P'
  run_module modules/20_create_user.sh run_create_user
  [ "$status" -eq 0 ]
  mock_called usermod
  run grep -q '^chpasswd' "$MOCK_LOG"
  [ "$status" -ne 0 ]
}

# --- 30_generate_keys ------------------------------------------------------

@test "30_generate_keys creates keys and is idempotent" {
  run_module modules/30_generate_keys.sh run_generate_keys
  [ "$status" -eq 0 ]
  [ -s "$WG_ROOT/etc/wireguard/wg0_server_private.key" ]
  [ -s "$WG_ROOT/etc/wireguard/wg0_client_preshared.key" ]
  # The private key must be owner-only.
  run ls -l "$WG_ROOT/etc/wireguard/wg0_server_private.key"
  [[ "$output" == -rw-------* ]]
  cp "$WG_ROOT/etc/wireguard/wg0_server_private.key" "$BATS_TEST_TMPDIR/first"
  run_module modules/30_generate_keys.sh run_generate_keys
  [ "$status" -eq 0 ]
  diff "$BATS_TEST_TMPDIR/first" \
    "$WG_ROOT/etc/wireguard/wg0_server_private.key"
}

@test "30_generate_keys fails when key generation fails" {
  export MOCK_FAIL='wg'
  run_module modules/30_generate_keys.sh run_generate_keys
  [ "$status" -ne 0 ]
}

# --- 40_write_server_conf --------------------------------------------------

@test "40_write_server_conf writes the interface config and backs it up" {
  export WG_PORT='51820'
  export VPN_SUBNET='10.13.13.0/24'
  run_module modules/30_generate_keys.sh run_generate_keys
  run_module modules/40_write_server_conf.sh run_write_server_conf
  [ "$status" -eq 0 ]
  grep -q '^\[Interface\]' "$WG_ROOT/etc/wireguard/wg0.conf"
  grep -q '^ListenPort = 51820' "$WG_ROOT/etc/wireguard/wg0.conf"
  grep -q '^Address = 10.13.13.1/24' "$WG_ROOT/etc/wireguard/wg0.conf"
  # A second run backs up the existing config (RF-13).
  run_module modules/40_write_server_conf.sh run_write_server_conf
  [ "$status" -eq 0 ]
  run find "$WG_ROOT/etc/wireguard/backups" -name 'wg0.conf'
  [ -n "$output" ]
}

@test "40_write_server_conf drops the previous masquerade on a subnet change" {
  export WG_PORT='51820'
  export VPN_SUBNET='10.13.13.0/24'
  run_module modules/30_generate_keys.sh run_generate_keys
  run_module modules/40_write_server_conf.sh run_write_server_conf
  [ "$status" -eq 0 ]
  # Re-install with a different subnet: the rewritten conf loses the old
  # PostDown, so the live rule for the previous subnet would linger until
  # reboot (audit F1) — module 40 must delete it explicitly.
  export VPN_SUBNET='10.14.14.0/24'
  run_module modules/40_write_server_conf.sh run_write_server_conf
  [ "$status" -eq 0 ]
  grep -q 'iptables -t nat -D POSTROUTING -s 10.13.13.0/24' "$MOCK_LOG"
  grep -q '^Address = 10.14.14.1/24' "$WG_ROOT/etc/wireguard/wg0.conf"
}

@test "40_write_server_conf keeps the masquerade when nothing changed" {
  export WG_PORT='51820'
  export VPN_SUBNET='10.13.13.0/24'
  run_module modules/30_generate_keys.sh run_generate_keys
  run_module modules/40_write_server_conf.sh run_write_server_conf
  [ "$status" -eq 0 ]
  run_module modules/40_write_server_conf.sh run_write_server_conf
  [ "$status" -eq 0 ]
  ! grep -q 'iptables -t nat -D POSTROUTING' "$MOCK_LOG"
}

@test "40_write_server_conf fails when the keys are missing" {
  export VPN_SUBNET='10.13.13.0/24'
  run_module modules/40_write_server_conf.sh run_write_server_conf
  [ "$status" -ne 0 ]
}

@test "40_write_server_conf writes PostUp/PostDown so NAT+forward survive reboot" {
  # The NAT masquerade and FORWARD rules must be restored by wg-quick on every
  # interface start, otherwise the VPN loses internet after the first reboot
  # (audit H2 — nothing persisted them before).
  export VPN_SUBNET='10.13.13.0/24'
  run_module modules/30_generate_keys.sh run_generate_keys
  run_module modules/40_write_server_conf.sh run_write_server_conf
  [ "$status" -eq 0 ]
  local conf="$WG_ROOT/etc/wireguard/wg0.conf"
  grep -q '^PostUp = .*POSTROUTING .*MASQUERADE' "$conf"
  grep -q '^PostUp = .*FORWARD' "$conf"
  grep -q '^PostDown = .*POSTROUTING .*-j MASQUERADE' "$conf"
  grep -q '^PostDown = .*FORWARD' "$conf"
}

@test "v2 routed server config uses authoritative slots and peer host routes" {
  setup_v2_network_result routed
  run_module modules/30_generate_keys.sh run_generate_keys
  run_module modules/40_write_server_conf.sh run_write_server_conf
  [ "$status" -eq 0 ]
  local conf="$WG_ROOT/etc/wireguard/wg0.conf"
  grep -q '^Address = 10.13.13.1/24, 2600:abcd:1234:5678::1/64$' "$conf"
  grep -q '^AllowedIPs = 10.13.13.2/32, 2600:abcd:1234:5678::2/128$' "$conf"
  ! grep -q '^AllowedIPs = .*\/0' "$conf"
  [ -x "$WG_ROOT/etc/wireguard/fav/lib/profile_renderer.py" ]
}

@test "v2 refuses to replace an existing configuration" {
  setup_v2_network_result blocked
  mkdir -p "$WG_ROOT/etc/wireguard"
  printf 'existing peer\n' >"$WG_ROOT/etc/wireguard/wg0.conf"
  run_module modules/30_generate_keys.sh run_generate_keys
  run_module modules/40_write_server_conf.sh run_write_server_conf
  [ "$status" -ne 0 ]
  grep -qx 'existing peer' "$WG_ROOT/etc/wireguard/wg0.conf"
}

# --- 50_enable_forwarding --------------------------------------------------

@test "50_enable_forwarding enables IPv4 forwarding" {
  run_module modules/50_enable_forwarding.sh run_enable_forwarding
  [ "$status" -eq 0 ]
  grep -q 'net.ipv4.ip_forward = 1' \
    "$WG_ROOT/etc/sysctl.d/99-wireguard.conf"
  mock_called sysctl
}

@test "50_enable_forwarding fails when sysctl fails" {
  export MOCK_FAIL='sysctl'
  run_module modules/50_enable_forwarding.sh run_enable_forwarding
  [ "$status" -ne 0 ]
}

# --- 60_firewall -----------------------------------------------------------

@test "60_firewall adds a masquerade rule" {
  export VPN_SUBNET='10.13.13.0/24'
  run_module modules/60_firewall.sh run_firewall
  [ "$status" -eq 0 ]
  grep -q 'iptables -t nat -A POSTROUTING' "$MOCK_LOG"
}

@test "60_firewall fails when iptables fails" {
  export VPN_SUBNET='10.13.13.0/24'
  export MOCK_FAIL='iptables'
  run_module modules/60_firewall.sh run_firewall
  [ "$status" -ne 0 ]
}

@test "60_firewall detects the WAN on a 'default dev pppX' route" {
  # A PPPoE / scope-link default route has no `via GW`, so the interface is not
  # field 5. The masquerade must still target the real WAN, not fall back to
  # eth0 (audit M5).
  export VPN_SUBNET='10.13.13.0/24'
  export MOCK_IP_ROUTE='default dev ppp0 scope link'
  run_module modules/60_firewall.sh run_firewall
  [ "$status" -eq 0 ]
  grep -q 'iptables -t nat -A POSTROUTING -s 10.13.13.0/24 -o ppp0' "$MOCK_LOG"
}

# --- 70_start_service ------------------------------------------------------

@test "70_start_service permits the FAV Python helper in Ubuntu AppArmor" {
  local profile="$WG_ROOT/etc/apparmor.d/wg-quick"
  local rule="$WG_ROOT/etc/apparmor.d/local/wg-quick"
  mkdir -p "$(dirname "$profile")"
  printf '%s\n' 'include if exists <local/wg-quick>' >"$profile"

  run_module modules/70_start_service.sh run_start_service
  [ "$status" -eq 0 ]
  grep -q '/usr/bin/python3.\[0-9\]\* rPUx,' "$rule"
  mock_called apparmor_parser
}

@test "70_start_service enables and restarts wg-quick" {
  run_module modules/70_start_service.sh run_start_service
  [ "$status" -eq 0 ]
  grep -q 'systemctl enable wg-quick@wg0' "$MOCK_LOG"
  # restart (not just enable --now) so a re-install applies the fresh config
  # even when the interface is already up (audit M-restart).
  grep -q 'systemctl restart wg-quick@wg0' "$MOCK_LOG"
}

@test "70_start_service fails when the service cannot start" {
  export MOCK_FAIL='systemctl'
  run_module modules/70_start_service.sh run_start_service
  [ "$status" -ne 0 ]
}

# --- 25_deploy_app_key -----------------------------------------------------

setup_deploy_app_key_env() {
  export SSH_PUBKEY='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBcDeFGhIjKlMnOpQrSt fav@dev'
}

@test "25_deploy_app_key authorizes the key for NEW_USERNAME" {
  setup_deploy_app_key_env
  export NEW_USERNAME='deploy'
  run_module modules/25_deploy_app_key.sh run_deploy_app_key
  [ "$status" -eq 0 ]
  [ -f "$WG_ROOT/home/deploy/.ssh/authorized_keys" ]
  grep -qxF "$SSH_PUBKEY" "$WG_ROOT/home/deploy/.ssh/authorized_keys"
}

@test "25_deploy_app_key authorizes the key for root when NEW_USERNAME is unset" {
  setup_deploy_app_key_env
  run_module modules/25_deploy_app_key.sh run_deploy_app_key
  [ "$status" -eq 0 ]
  # Default sandboxed home for `root` is $WG_ROOT/home/root via the mocked
  # getent — sufficient to assert the deploy targeted the root account.
  [ -f "$WG_ROOT/home/root/.ssh/authorized_keys" ]
  grep -qxF "$SSH_PUBKEY" "$WG_ROOT/home/root/.ssh/authorized_keys"
}

@test "25_deploy_app_key is idempotent on re-run" {
  setup_deploy_app_key_env
  export NEW_USERNAME='deploy'
  run_module modules/25_deploy_app_key.sh run_deploy_app_key
  [ "$status" -eq 0 ]
  run_module modules/25_deploy_app_key.sh run_deploy_app_key
  [ "$status" -eq 0 ]
  run grep -cxF "$SSH_PUBKEY" "$WG_ROOT/home/deploy/.ssh/authorized_keys"
  [ "$output" -eq 1 ]
}

@test "25_deploy_app_key rejects an SSH_PUBKEY with the wrong key type" {
  export SSH_PUBKEY='ssh-rsa AAAAB3Nz fav@dev'
  run_module modules/25_deploy_app_key.sh run_deploy_app_key
  [ "$status" -ne 0 ]
}

@test "25_deploy_app_key rejects an SSH_PUBKEY that spans multiple lines" {
  export SSH_PUBKEY=$'ssh-ed25519 AAAA\n attacker-line'
  run_module modules/25_deploy_app_key.sh run_deploy_app_key
  [ "$status" -ne 0 ]
}

@test "25_deploy_app_key aborts when SSH_PUBKEY is missing" {
  run_module modules/25_deploy_app_key.sh run_deploy_app_key
  [ "$status" -ne 0 ]
}

@test "25_deploy_app_key does not leak the public key into the command log" {
  setup_deploy_app_key_env
  export NEW_USERNAME='deploy'
  run_module modules/25_deploy_app_key.sh run_deploy_app_key
  [ "$status" -eq 0 ]
  run grep -F "$SSH_PUBKEY" "$MOCK_LOG"
  [ "$status" -ne 0 ]
}

# --- 26_deploy_user_keys ---------------------------------------------------

# Encodes its newline-joined arguments as the base64 blob the module expects.
encode_user_keys() {
  local joined
  joined="$(printf '%s\n' "$@")"
  # Strip the trailing newline printf adds after the last key.
  joined="${joined%$'\n'}"
  printf '%s' "$joined" | base64 | tr -d '\n'
}

@test "26_deploy_user_keys deploys every key for NEW_USERNAME" {
  local k1='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBcDeFGhIjKlMnOpQrSt user@laptop'
  local k2='ssh-rsa AAAAB3NzaC1yc2E= desktop'
  export USER_AUTHORIZED_KEYS_B64="$(encode_user_keys "$k1" "$k2")"
  export NEW_USERNAME='deploy'
  run_module modules/26_deploy_user_keys.sh run_deploy_user_keys
  [ "$status" -eq 0 ]
  grep -qxF "$k1" "$WG_ROOT/home/deploy/.ssh/authorized_keys"
  grep -qxF "$k2" "$WG_ROOT/home/deploy/.ssh/authorized_keys"
}

@test "26_deploy_user_keys targets root when NEW_USERNAME is unset" {
  local k1='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBcDeFGhIjKlMnOpQrSt user@laptop'
  export USER_AUTHORIZED_KEYS_B64="$(encode_user_keys "$k1")"
  run_module modules/26_deploy_user_keys.sh run_deploy_user_keys
  [ "$status" -eq 0 ]
  grep -qxF "$k1" "$WG_ROOT/home/root/.ssh/authorized_keys"
}

@test "26_deploy_user_keys is idempotent on re-run" {
  local k1='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBcDeFGhIjKlMnOpQrSt user@laptop'
  export USER_AUTHORIZED_KEYS_B64="$(encode_user_keys "$k1")"
  export NEW_USERNAME='deploy'
  run_module modules/26_deploy_user_keys.sh run_deploy_user_keys
  [ "$status" -eq 0 ]
  run_module modules/26_deploy_user_keys.sh run_deploy_user_keys
  [ "$status" -eq 0 ]
  run grep -cxF "$k1" "$WG_ROOT/home/deploy/.ssh/authorized_keys"
  [ "$output" -eq 1 ]
}

@test "26_deploy_user_keys skips lines with an unrecognized key type" {
  local good='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBcDeFGhIjKlMnOpQrSt user@laptop'
  local bad='rm -rf / # not-a-key'
  export USER_AUTHORIZED_KEYS_B64="$(encode_user_keys "$bad" "$good")"
  export NEW_USERNAME='deploy'
  run_module modules/26_deploy_user_keys.sh run_deploy_user_keys
  [ "$status" -eq 0 ]
  grep -qxF "$good" "$WG_ROOT/home/deploy/.ssh/authorized_keys"
  run grep -F "rm -rf" "$WG_ROOT/home/deploy/.ssh/authorized_keys"
  [ "$status" -ne 0 ]
}

@test "26_deploy_user_keys does nothing when the blob is empty" {
  export USER_AUTHORIZED_KEYS_B64=''
  export NEW_USERNAME='deploy'
  run_module modules/26_deploy_user_keys.sh run_deploy_user_keys
  [ "$status" -eq 0 ]
  [ ! -f "$WG_ROOT/home/deploy/.ssh/authorized_keys" ]
}

@test "26_deploy_user_keys aborts on invalid base64" {
  export USER_AUTHORIZED_KEYS_B64='!!!not-base64!!!'
  export NEW_USERNAME='deploy'
  run_module modules/26_deploy_user_keys.sh run_deploy_user_keys
  [ "$status" -ne 0 ]
}

# --- 80_hardening ----------------------------------------------------------

@test "80_hardening installs fail2ban and writes the jail" {
  run_module modules/80_hardening.sh run_hardening
  [ "$status" -eq 0 ]
  mock_called apt-get
  mock_called systemctl
  [ -f "$WG_ROOT/etc/fail2ban/jail.d/sshd.local" ]
  grep -q '^enabled = true' "$WG_ROOT/etc/fail2ban/jail.d/sshd.local"
  grep -q '^maxretry = 3'   "$WG_ROOT/etc/fail2ban/jail.d/sshd.local"
  grep -q '^bantime  = 1h'  "$WG_ROOT/etc/fail2ban/jail.d/sshd.local"
}

@test "80_hardening is idempotent on re-run" {
  run_module modules/80_hardening.sh run_hardening
  [ "$status" -eq 0 ]
  run_module modules/80_hardening.sh run_hardening
  [ "$status" -eq 0 ]
}

# --- 90_health_check -------------------------------------------------------

@test "90_health_check passes when the interface is up and the port listens" {
  export WG_PORT='51820'
  run_module modules/90_health_check.sh run_health_check
  [ "$status" -eq 0 ]
}

@test "90_health_check fails when the listen port is not open" {
  export WG_PORT='9999'
  run_module modules/90_health_check.sh run_health_check
  [ "$status" -ne 0 ]
}

# --- 99_finalize -----------------------------------------------------------

@test "99_finalize writes the client profile" {
  export WG_PORT='51820'
  export VPN_SUBNET='10.13.13.0/24'
  export PUBLIC_ENDPOINT='203.0.113.10'
  export RUN_DIR="$BATS_TEST_TMPDIR/run"
  mkdir -p "$RUN_DIR"
  run_module modules/30_generate_keys.sh run_generate_keys
  run_module modules/99_finalize.sh run_finalize
  [ "$status" -eq 0 ]
  grep -q '^\[Interface\]' "$RUN_DIR/client.conf"
  grep -q '^Endpoint = 203.0.113.10:51820' "$RUN_DIR/client.conf"
  grep -q '^AllowedIPs = 0.0.0.0/0' "$RUN_DIR/client.conf"
}

@test "99_finalize fails when RUN_DIR is unset" {
  run_module modules/30_generate_keys.sh run_generate_keys
  unset RUN_DIR
  run_module modules/99_finalize.sh run_finalize
  [ "$status" -ne 0 ]
}

@test "99_finalize fails on an empty PUBLIC_ENDPOINT" {
  # An empty endpoint would emit an unusable `Endpoint = :51820` profile
  # (audit L2).
  export RUN_DIR="$BATS_TEST_TMPDIR/run"
  mkdir -p "$RUN_DIR"
  export PUBLIC_ENDPOINT=''
  run_module modules/30_generate_keys.sh run_generate_keys
  run_module modules/99_finalize.sh run_finalize
  [ "$status" -ne 0 ]
  [ ! -e "$RUN_DIR/client.conf" ]
}

@test "80_hardening bans on the configured SSH port and restarts the jail" {
  export SSH_PORT=2222
  run_module modules/80_hardening.sh run_hardening
  [ "$status" -eq 0 ]
  grep -q '^port    = 2222' "$WG_ROOT/etc/fail2ban/jail.d/sshd.local"
  grep -q '^systemctl restart fail2ban' "$MOCK_LOG"
}

@test "99_finalize brackets IPv6 endpoints without double brackets" {
  mkdir -p "$WG_ROOT/etc/wireguard"
  printf 'private\n' > "$WG_ROOT/etc/wireguard/wg0_client_private.key"
  printf 'public\n' > "$WG_ROOT/etc/wireguard/wg0_server_public.key"
  printf 'psk\n' > "$WG_ROOT/etc/wireguard/wg0_client_preshared.key"
  export RUN_DIR="$BATS_TEST_TMPDIR/run"
  mkdir -p "$RUN_DIR"
  for endpoint in '2001:db8::1' '[2001:db8::1]'; do
    export PUBLIC_ENDPOINT="$endpoint"
    run_module modules/99_finalize.sh run_finalize
    [ "$status" -eq 0 ]
    grep -qF 'Endpoint = [2001:db8::1]:51820' "$RUN_DIR/client.conf"
  done
}

@test "v2 blocked client uses ULA, mixed DNS, MTU and both default routes" {
  setup_v2_network_result blocked
  run_module modules/30_generate_keys.sh run_generate_keys
  run_module modules/40_write_server_conf.sh run_write_server_conf
  run_module modules/99_finalize.sh run_finalize
  [ "$status" -eq 0 ]
  grep -q '^Address = 10.13.13.2/32, fd12:3456:789a::2/128$' "$RUN_DIR/client.conf"
  grep -q '^DNS = 1.1.1.1, 2606:4700:4700::1111$' "$RUN_DIR/client.conf"
  grep -q '^MTU = 1420$' "$RUN_DIR/client.conf"
  grep -q '^AllowedIPs = 0.0.0.0/0, ::/0$' "$RUN_DIR/client.conf"
  grep -q '"endpointHost":"vpn.example.org"' "$WG_ROOT/etc/wireguard/fav/wg0/manifest.json"
}

@test "v2 rejects network-result mismatch and IPv6-only DNS in blocked mode" {
  setup_v2_network_result blocked
  sed -i.bak 's/10.13.13.0\/24/10.14.14.0\/24/' "$RUN_DIR/network-result.json"
  run_module modules/30_generate_keys.sh run_generate_keys
  run_module modules/40_write_server_conf.sh run_write_server_conf
  [ "$status" -ne 0 ]
  rm -f "$WG_ROOT/etc/wireguard/wg0.conf"
  setup_v2_network_result blocked
  export DNS='2606:4700:4700::1111'
  run_module modules/40_write_server_conf.sh run_write_server_conf
  [ "$status" -ne 0 ]
}
