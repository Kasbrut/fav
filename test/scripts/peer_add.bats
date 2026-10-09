#!/usr/bin/env bats
# Tests for peers/peer_add.sh (multi-peer v1.1).

load test_helper

setup() {
  install_mocks "$BATS_TEST_TMPDIR/bin"
  export PATH
  export MOCK_LOG="$BATS_TEST_TMPDIR/mock.log"
  : >"$MOCK_LOG"
  export MOCK_WG_PEERS_FILE="$BATS_TEST_TMPDIR/wg_peers"
  : >"$MOCK_WG_PEERS_FILE"
  export WG_ROOT="$BATS_TEST_TMPDIR/root"
  mkdir -p "$WG_ROOT/etc/wireguard"
  # Seed the server keys the way 30_generate_keys.sh would have left them.
  printf 'SERVER-PRIV\n' >"$WG_ROOT/etc/wireguard/wg0_server_private.key"
  printf 'SERVER-PUB\n' >"$WG_ROOT/etc/wireguard/wg0_server_public.key"
  chmod 600 "$WG_ROOT/etc/wireguard/"*.key
  export INTERFACE_NAME='wg0'
  export VPN_SUBNET='10.13.13.0/24'
  export PUBLIC_ENDPOINT='vpn.example.org'
  export WG_PORT='51820'
  export DNS='1.1.1.1, 1.0.0.1'
  export MTU='1420'
  export PEER_LABEL='phone'
  PEER_ADD="$SCRIPTS_DIR/peers/peer_add.sh"
}

# Writes a baseline wg0.conf with the server [Interface] and an existing
# first-client [Peer] block at .2 — i.e. the state after install.
seed_conf_with_first_peer() {
  cat >"$WG_ROOT/etc/wireguard/wg0.conf" <<'CONF'
[Interface]
Address = 10.13.13.1/24
ListenPort = 51820
MTU = 1420
PrivateKey = SERVER-PRIV

[Peer]
PublicKey = FIRST-PEER-PUB
PresharedKey = FIRST-PEER-PSK
AllowedIPs = 10.13.13.2/32
CONF
  chmod 600 "$WG_ROOT/etc/wireguard/wg0.conf"
  # The first peer's pubkey is already on the wire.
  printf 'FIRST-PEER-PUB\n' >"$MOCK_WG_PEERS_FILE"
}

# --- happy paths ----------------------------------------------------------

@test "peer_add assigns .3 when wg0.conf has only the first peer at .2" {
  seed_conf_with_first_peer
  run bash "$PEER_ADD"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ADDR=10.13.13.3/32"* ]]
  [[ "$output" == *"PUBKEY=CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC="* ]]
  [[ "$output" == *"---BEGIN-CONF---"* ]]
  [[ "$output" == *"---END-CONF---"* ]]
  # The interface conf now has the new peer's address.
  grep -q '10.13.13.3/32' "$WG_ROOT/etc/wireguard/wg0.conf"
  # The peer was applied at runtime via `wg set`.
  mock_called wg
  grep -F 'wg set wg0 peer' "$MOCK_LOG"
}

@test "peer_add assigns .4 when two peers are already present" {
  cat >"$WG_ROOT/etc/wireguard/wg0.conf" <<'CONF'
[Interface]
Address = 10.13.13.1/24
ListenPort = 51820
PrivateKey = SERVER-PRIV

[Peer]
PublicKey = FIRST-PEER-PUB
AllowedIPs = 10.13.13.2/32

[Peer]
PublicKey = SECOND-PEER-PUB
AllowedIPs = 10.13.13.3/32
CONF
  run bash "$PEER_ADD"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ADDR=10.13.13.4/32"* ]]
}

@test "peer_add fills the hole left by a revoke (.3 reusable)" {
  # Two peers at .2 and .4 — .3 has been revoked, so the allocator must pick
  # the smallest free address in the subnet.
  cat >"$WG_ROOT/etc/wireguard/wg0.conf" <<'CONF'
[Interface]
Address = 10.13.13.1/24
ListenPort = 51820
PrivateKey = SERVER-PRIV

[Peer]
PublicKey = FIRST-PEER-PUB
AllowedIPs = 10.13.13.2/32

[Peer]
PublicKey = FOURTH-PEER-PUB
AllowedIPs = 10.13.13.4/32
CONF
  run bash "$PEER_ADD"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ADDR=10.13.13.3/32"* ]]
}

@test "peer_add ignores [Peer] blocks under the backups directory" {
  seed_conf_with_first_peer
  # An old backup of wg0.conf must NOT confuse the allocator.
  mkdir -p "$WG_ROOT/etc/wireguard/backups/20250101000000"
  cp "$WG_ROOT/etc/wireguard/wg0.conf" \
    "$WG_ROOT/etc/wireguard/backups/20250101000000/wg0.conf"
  # Pollute the backup with an extra peer at .3 to prove it's ignored.
  cat >>"$WG_ROOT/etc/wireguard/backups/20250101000000/wg0.conf" <<'CONF'

[Peer]
PublicKey = BACKUP-PEER-PUB
AllowedIPs = 10.13.13.3/32
CONF
  run bash "$PEER_ADD"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ADDR=10.13.13.3/32"* ]]
}

# --- envelope shape -------------------------------------------------------

@test "peer_add emits a well-formed envelope with the client.conf body" {
  seed_conf_with_first_peer
  run bash "$PEER_ADD"
  [ "$status" -eq 0 ]
  # Extract the body strictly between sentinels and verify it looks like a
  # WireGuard client conf.
  body=$(printf '%s\n' "$output" |
    awk '/^---BEGIN-CONF---$/{p=1;next}/^---END-CONF---$/{p=0}p')
  [[ "$body" == *"[Interface]"* ]]
  [[ "$body" == *"PrivateKey = AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="* ]]
  [[ "$body" == *"Address = 10.13.13.3/32"* ]]
  [[ "$body" == *"DNS = 1.1.1.1, 1.0.0.1"* ]]
  [[ "$body" == *"MTU = 1420"* ]]
  [[ "$body" == *"[Peer]"* ]]
  [[ "$body" == *"PublicKey = SERVER-PUB"* ]]
  [[ "$body" == *"PresharedKey = BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB="* ]]
  [[ "$body" == *"Endpoint = vpn.example.org:51820"* ]]
  [[ "$body" == *"AllowedIPs = 0.0.0.0/0"* ]]
  [[ "$body" == *"PersistentKeepalive = 25"* ]]
}

# --- error paths ----------------------------------------------------------

@test "peer_add exits ERR-PEER-SUBNET-EXHAUSTED when the /24 is full" {
  # Build a wg0.conf with every host address taken (.2 through .254).
  {
    cat <<'HDR'
[Interface]
Address = 10.13.13.1/24
ListenPort = 51820
PrivateKey = SERVER-PRIV

HDR
    for i in $(seq 2 254); do
      printf '[Peer]\nPublicKey = PEER-%s\nAllowedIPs = 10.13.13.%s/32\n\n' \
        "$i" "$i"
    done
  } >"$WG_ROOT/etc/wireguard/wg0.conf"
  run bash "$PEER_ADD"
  [ "$status" -eq 41 ]
  [[ "$stderr" == *"ERR-PEER-SUBNET-EXHAUSTED"* ]] || \
    [[ "$output" == *"ERR-PEER-SUBNET-EXHAUSTED"* ]]
}

@test "peer_add rolls back the [Peer] block when wg set fails" {
  seed_conf_with_first_peer
  before=$(wc -l <"$WG_ROOT/etc/wireguard/wg0.conf")
  export MOCK_WG_SET_FAIL=1
  run bash "$PEER_ADD"
  [ "$status" -eq 40 ]
  [[ "$output" == *"ERR-PEER-APPLY-FAILED"* ]] || \
    [[ "$stderr" == *"ERR-PEER-APPLY-FAILED"* ]]
  after=$(wc -l <"$WG_ROOT/etc/wireguard/wg0.conf")
  # The appended block must be gone — line count back to the pre-add value
  # (within a trailing-blank-line tolerance).
  diff=$(( after - before ))
  [ "$diff" -ge -1 ] && [ "$diff" -le 1 ]
  # .3 must not be present in the conf.
  ! grep -q '10.13.13.3/32' "$WG_ROOT/etc/wireguard/wg0.conf"
}

@test "peer_add sanitizes a malicious PEER_LABEL before writing the comment" {
  seed_conf_with_first_peer
  export PEER_LABEL='phone$(rm -rf /tmp/x)`whoami`'
  run bash "$PEER_ADD"
  [ "$status" -eq 0 ]
  # The dollar-paren and backtick substitutions must not survive sanitisation.
  ! grep -F '$(rm' "$WG_ROOT/etc/wireguard/wg0.conf"
  ! grep -F '`whoami`' "$WG_ROOT/etc/wireguard/wg0.conf"
  # Some recognisable prefix from the label is preserved.
  grep -F '# label: phone' "$WG_ROOT/etc/wireguard/wg0.conf"
}

@test "peer_add acquires the per-interface flock" {
  seed_conf_with_first_peer
  run bash "$PEER_ADD"
  [ "$status" -eq 0 ]
  mock_called flock
}

@test "peer_add never writes any key material to the mock log" {
  seed_conf_with_first_peer
  run bash "$PEER_ADD"
  [ "$status" -eq 0 ]
  # The mock-generated key/PSK strings must never appear in the log.
  ! grep -q 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=' "$MOCK_LOG"
  ! grep -q 'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=' "$MOCK_LOG"
}

@test "peer_add emits a bracketed IPv6 endpoint" {
  export PUBLIC_ENDPOINT='2001:db8::1'
  run bash "$SCRIPTS_DIR/peers/peer_add.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *'Endpoint = [2001:db8::1]:51820'* ]]
}
