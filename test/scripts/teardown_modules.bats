# Tests for the individual teardown modules.
# shellcheck shell=bats

setup() {
  load test_helper
  BIN_DIR="$BATS_TEST_TMPDIR/bin"
  export MOCK_LOG="$BATS_TEST_TMPDIR/mock.log"
  : >"$MOCK_LOG"
  install_mocks "$BIN_DIR"
  export WG_ROOT="$BATS_TEST_TMPDIR/root"
  mkdir -p "$WG_ROOT"
}

@test "stop_service disables the wg-quick unit" {
  run_module teardown/modules/10_stop_service.sh run_stop_service
  [ "$status" -eq 0 ]
  mock_called systemctl
}

@test "stop_service is idempotent on a second run" {
  run_module teardown/modules/10_stop_service.sh run_stop_service
  [ "$status" -eq 0 ]
  run_module teardown/modules/10_stop_service.sh run_stop_service
  [ "$status" -eq 0 ]
}

@test "remove_monitor deletes every monitor artifact and reloads systemd" {
  mkdir -p "$WG_ROOT/usr/local/bin" \
    "$WG_ROOT/etc/systemd/system" \
    "$WG_ROOT/etc/logrotate.d" "$WG_ROOT/etc/fav"
  touch "$WG_ROOT/usr/local/bin/wg-monitor.sh" \
    "$WG_ROOT/etc/systemd/system/wg-monitor.service" \
    "$WG_ROOT/etc/systemd/system/wg-monitor.timer" \
    "$WG_ROOT/etc/logrotate.d/fav" "$WG_ROOT/etc/fav/monitor.env"

  run_module teardown/modules/20_remove_monitor.sh run_remove_monitor
  [ "$status" -eq 0 ]
  [ ! -e "$WG_ROOT/usr/local/bin/wg-monitor.sh" ]
  [ ! -e "$WG_ROOT/etc/systemd/system/wg-monitor.service" ]
  [ ! -e "$WG_ROOT/etc/systemd/system/wg-monitor.timer" ]
  [ ! -e "$WG_ROOT/etc/logrotate.d/fav" ]
  [ ! -e "$WG_ROOT/etc/fav/monitor.env" ]
  mock_called systemctl
}

@test "remove_monitor also removes the monitor data directories" {
  # The monitor writes peers-state.json + events.jsonl under /var/lib/fav and
  # /var/log/fav; these must be removed too (audit H3).
  export WG_MONITOR_STATE_DIR="$WG_ROOT/var/lib/fav"
  export WG_MONITOR_LOG_DIR="$WG_ROOT/var/log/fav"
  export WG_MONITOR_RUNTIME_DIR="$WG_ROOT/run/fav"
  mkdir -p "$WG_MONITOR_STATE_DIR" "$WG_MONITOR_LOG_DIR" \
    "$WG_MONITOR_RUNTIME_DIR"
  printf '{}' >"$WG_MONITOR_STATE_DIR/peers-state.json"
  printf '{}\n' >"$WG_MONITOR_LOG_DIR/events.jsonl"

  run_module teardown/modules/20_remove_monitor.sh run_remove_monitor
  [ "$status" -eq 0 ]
  [ ! -e "$WG_MONITOR_STATE_DIR" ]
  [ ! -e "$WG_MONITOR_LOG_DIR" ]
  [ ! -e "$WG_MONITOR_RUNTIME_DIR" ]
}

@test "remove_monitor is idempotent when nothing is installed" {
  run_module teardown/modules/20_remove_monitor.sh run_remove_monitor
  [ "$status" -eq 0 ]
}

@test "remove_firewall deletes the NAT masquerade rule" {
  run_module teardown/modules/30_remove_firewall.sh run_remove_firewall
  [ "$status" -eq 0 ]
  mock_called iptables
}

@test "remove_firewall runs the -D delete loop while a rule lingers" {
  # The default mock's `iptables -C` always reports absent, so the delete
  # loops were never exercised (teardown follow-up). Report the rule
  # present once: the loop must fire exactly one -D and then terminate.
  export MOCK_IPTABLES_PRESENT="$BATS_TEST_TMPDIR/iptables-present"
  printf '1' >"$MOCK_IPTABLES_PRESENT"
  run_module teardown/modules/30_remove_firewall.sh run_remove_firewall
  [ "$status" -eq 0 ]
  grep -q -- '-t nat -D POSTROUTING' "$MOCK_LOG"
}

@test "remove_forwarding deletes the sysctl drop-in and reloads" {
  mkdir -p "$WG_ROOT/etc/sysctl.d"
  printf 'net.ipv4.ip_forward = 1\n' \
    >"$WG_ROOT/etc/sysctl.d/99-wireguard.conf"

  run_module teardown/modules/40_remove_forwarding.sh run_remove_forwarding
  [ "$status" -eq 0 ]
  [ ! -e "$WG_ROOT/etc/sysctl.d/99-wireguard.conf" ]
  mock_called sysctl
}

@test "remove_forwarding is idempotent when the drop-in is absent" {
  run_module teardown/modules/40_remove_forwarding.sh run_remove_forwarding
  [ "$status" -eq 0 ]
}

@test "remove_config deletes the wireguard config and every key file" {
  mkdir -p "$WG_ROOT/etc/wireguard"
  printf '[Interface]\n' >"$WG_ROOT/etc/wireguard/wg0.conf"
  # The installer's real key file names (30_generate_keys.sh): server/client
  # private + public and the preshared key, all `wg0_*.key`.
  for k in server_private server_public client_private client_public \
    client_preshared; do
    printf 'KEYDATA\n' >"$WG_ROOT/etc/wireguard/wg0_$k.key"
  done

  run_module teardown/modules/50_remove_config.sh run_remove_config
  [ "$status" -eq 0 ]
  [ ! -e "$WG_ROOT/etc/wireguard/wg0.conf" ]
  # No key file — especially no *private* key — is left behind.
  run bash -c "ls $WG_ROOT/etc/wireguard/wg0_*.key 2>/dev/null"
  [ -z "$output" ]
}

@test "remove_config also removes per-peer keys, backups and the lock" {
  # peer_add.sh writes per-peer client private keys + PSKs under peers/, and
  # 40_write_server_conf.sh backs up previous configs (with the server private
  # key + PSK) under backups/. Teardown must remove them too or key material
  # survives a "complete" removal (audit H3).
  mkdir -p "$WG_ROOT/etc/wireguard/peers/abcd1234" \
    "$WG_ROOT/etc/wireguard/backups/20260101000000"
  printf 'PEERPRIV\n' >"$WG_ROOT/etc/wireguard/peers/abcd1234/private.key"
  printf 'PEERPSK\n' >"$WG_ROOT/etc/wireguard/peers/abcd1234/preshared.key"
  printf '[Interface]\nPrivateKey = X\n' \
    >"$WG_ROOT/etc/wireguard/backups/20260101000000/wg0.conf"
  printf '' >"$WG_ROOT/etc/wireguard/wg0.lock"

  run_module teardown/modules/50_remove_config.sh run_remove_config
  [ "$status" -eq 0 ]
  [ ! -e "$WG_ROOT/etc/wireguard/peers" ]
  [ ! -e "$WG_ROOT/etc/wireguard/backups" ]
  [ ! -e "$WG_ROOT/etc/wireguard/wg0.lock" ]
}

@test "remove_config is idempotent when nothing is present" {
  run_module teardown/modules/50_remove_config.sh run_remove_config
  [ "$status" -eq 0 ]
}

@test "remove_fail2ban_jail deletes only FAV's jail file" {
  mkdir -p "$WG_ROOT/etc/fail2ban/jail.d"
  printf '[sshd]\nenabled = true\n' \
    >"$WG_ROOT/etc/fail2ban/jail.d/sshd.local"

  run_module teardown/modules/60_remove_fail2ban_jail.sh \
    run_remove_fail2ban_jail
  [ "$status" -eq 0 ]
  [ ! -e "$WG_ROOT/etc/fail2ban/jail.d/sshd.local" ]
}

@test "remove_fail2ban_jail is idempotent when the jail is absent" {
  run_module teardown/modules/60_remove_fail2ban_jail.sh \
    run_remove_fail2ban_jail
  [ "$status" -eq 0 ]
}
