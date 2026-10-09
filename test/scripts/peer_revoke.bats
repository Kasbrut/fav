#!/usr/bin/env bats
# Tests for peers/peer_revoke.sh (multi-peer v1.1).

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
  export INTERFACE_NAME='wg0'
  PEER_REVOKE="$SCRIPTS_DIR/peers/peer_revoke.sh"
}

# Writes a wg0.conf with the server [Interface] plus two peers (.2 and .3),
# and seeds the kernel side (MOCK_WG_PEERS_FILE) with both pubkeys.
seed_two_peers() {
  cat >"$WG_ROOT/etc/wireguard/wg0.conf" <<'CONF'
[Interface]
Address = 10.13.13.1/24
ListenPort = 51820
PrivateKey = SERVER-PRIV

# label: phone
[Peer]
PublicKey = FIRST-PEER-PUB
PresharedKey = FIRST-PSK
AllowedIPs = 10.13.13.2/32

# label: laptop
[Peer]
PublicKey = SECOND-PEER-PUB
PresharedKey = SECOND-PSK
AllowedIPs = 10.13.13.3/32
CONF
  chmod 600 "$WG_ROOT/etc/wireguard/wg0.conf"
  printf 'FIRST-PEER-PUB\nSECOND-PEER-PUB\n' >"$MOCK_WG_PEERS_FILE"
}

# --- happy paths ----------------------------------------------------------

@test "peer_revoke removes the matching [Peer] block and its `# label:`" {
  seed_two_peers
  export PEER_PUBKEY='FIRST-PEER-PUB'
  run bash "$PEER_REVOKE"
  [ "$status" -eq 0 ]
  # First peer's block is gone.
  ! grep -q 'FIRST-PEER-PUB' "$WG_ROOT/etc/wireguard/wg0.conf"
  ! grep -q '10.13.13.2/32' "$WG_ROOT/etc/wireguard/wg0.conf"
  # Preceding `# label: phone` comment is also stripped.
  ! grep -q '# label: phone' "$WG_ROOT/etc/wireguard/wg0.conf"
  # Second peer survives intact.
  grep -q 'SECOND-PEER-PUB' "$WG_ROOT/etc/wireguard/wg0.conf"
  grep -q '10.13.13.3/32' "$WG_ROOT/etc/wireguard/wg0.conf"
  grep -q '# label: laptop' "$WG_ROOT/etc/wireguard/wg0.conf"
  # The runtime call to wg set ... remove happened.
  grep -F 'wg set wg0 peer FIRST-PEER-PUB remove' "$MOCK_LOG"
}

@test "peer_revoke removes a peer whose PublicKey is a real base64 key (trailing =)" {
  # Real WireGuard public keys are 44 base64 chars ending in '='. The awk that
  # strips the [Peer] block must compare the whole value, not split on '='
  # (which drops the padding and never matches) — audit C2.
  local real_pub='hIWmAbCdEfGhIjKlMnOpQrStUvWxYz0123456789DXY='
  cat >"$WG_ROOT/etc/wireguard/wg0.conf" <<CONF
[Interface]
Address = 10.13.13.1/24
PrivateKey = SERVER-PRIV

# label: phone
[Peer]
PublicKey = ${real_pub}
PresharedKey = SOME-PSK
AllowedIPs = 10.13.13.2/32
CONF
  chmod 600 "$WG_ROOT/etc/wireguard/wg0.conf"
  printf '%s\n' "$real_pub" >"$MOCK_WG_PEERS_FILE"
  export PEER_PUBKEY="$real_pub"
  run bash "$PEER_REVOKE"
  [ "$status" -eq 0 ]
  # The whole [Peer] block — pubkey, PSK and AllowedIPs — must be gone.
  ! grep -qF "$real_pub" "$WG_ROOT/etc/wireguard/wg0.conf"
  ! grep -q 'SOME-PSK' "$WG_ROOT/etc/wireguard/wg0.conf"
  ! grep -q '10.13.13.2/32' "$WG_ROOT/etc/wireguard/wg0.conf"
}

@test "peer_revoke removes the last peer (no following section)" {
  seed_two_peers
  export PEER_PUBKEY='SECOND-PEER-PUB'
  run bash "$PEER_REVOKE"
  [ "$status" -eq 0 ]
  ! grep -q 'SECOND-PEER-PUB' "$WG_ROOT/etc/wireguard/wg0.conf"
  ! grep -q '# label: laptop' "$WG_ROOT/etc/wireguard/wg0.conf"
  grep -q 'FIRST-PEER-PUB' "$WG_ROOT/etc/wireguard/wg0.conf"
}

@test "peer_revoke removes the per-peer directory if it exists" {
  seed_two_peers
  # peer_add stores per-peer key material in a stable shorthash directory.
  # peer_revoke must clean it up — the path is derived from PEER_PUBKEY
  # the same way peer_add derived it. Here we exercise the cleanup path.
  pub_short='FIRSTPEERPUB'
  mkdir -p "$WG_ROOT/etc/wireguard/peers/${pub_short}"
  printf 'secret\n' >"$WG_ROOT/etc/wireguard/peers/${pub_short}/private.key"
  export PEER_PUBKEY='FIRST-PEER-PUB'
  run bash "$PEER_REVOKE"
  [ "$status" -eq 0 ]
  [ ! -d "$WG_ROOT/etc/wireguard/peers/${pub_short}" ]
}

@test "peer_revoke is robust against absent per-peer directory" {
  seed_two_peers
  export PEER_PUBKEY='FIRST-PEER-PUB'
  run bash "$PEER_REVOKE"
  [ "$status" -eq 0 ]
}

# --- error / edge paths ---------------------------------------------------

@test "peer_revoke returns ERR-PEER-NOT-FOUND for an unknown pubkey" {
  seed_two_peers
  export PEER_PUBKEY='UNKNOWN-PUB'
  export MOCK_WG_REMOVE_NOT_FOUND=1
  run bash "$PEER_REVOKE"
  [ "$status" -eq 42 ]
  [[ "$output" == *"ERR-PEER-NOT-FOUND"* ]] || \
    [[ "$stderr" == *"ERR-PEER-NOT-FOUND"* ]]
  # The conf must be unchanged.
  grep -q 'FIRST-PEER-PUB' "$WG_ROOT/etc/wireguard/wg0.conf"
  grep -q 'SECOND-PEER-PUB' "$WG_ROOT/etc/wireguard/wg0.conf"
}

@test "peer_revoke acquires the per-interface flock" {
  seed_two_peers
  export PEER_PUBKEY='FIRST-PEER-PUB'
  run bash "$PEER_REVOKE"
  [ "$status" -eq 0 ]
  mock_called flock
}

@test "peer_revoke matches PublicKey exactly (no substring matches)" {
  # A peer whose pubkey is a prefix of another's must NOT be removed when
  # the longer pubkey is targeted. The naive 'grep' approach would fail this.
  cat >"$WG_ROOT/etc/wireguard/wg0.conf" <<'CONF'
[Interface]
Address = 10.13.13.1/24
PrivateKey = SERVER-PRIV

# label: short
[Peer]
PublicKey = SHORT
AllowedIPs = 10.13.13.2/32

# label: longer
[Peer]
PublicKey = SHORTER
AllowedIPs = 10.13.13.3/32
CONF
  chmod 600 "$WG_ROOT/etc/wireguard/wg0.conf"
  printf 'SHORT\nSHORTER\n' >"$MOCK_WG_PEERS_FILE"
  export PEER_PUBKEY='SHORTER'
  run bash "$PEER_REVOKE"
  [ "$status" -eq 0 ]
  ! grep -qx 'PublicKey = SHORTER' "$WG_ROOT/etc/wireguard/wg0.conf"
  grep -qx 'PublicKey = SHORT'    "$WG_ROOT/etc/wireguard/wg0.conf"
}

@test "peer_revoke leaves an unrelated # label: comment alone" {
  # A `# label:` line that is NOT immediately followed by the deleted
  # [Peer] block must survive.
  cat >"$WG_ROOT/etc/wireguard/wg0.conf" <<'CONF'
[Interface]
Address = 10.13.13.1/24
PrivateKey = SERVER-PRIV

# label: standalone-comment-not-in-front-of-anything

# label: target
[Peer]
PublicKey = TARGET-PUB
AllowedIPs = 10.13.13.5/32
CONF
  printf 'TARGET-PUB\n' >"$MOCK_WG_PEERS_FILE"
  export PEER_PUBKEY='TARGET-PUB'
  run bash "$PEER_REVOKE"
  [ "$status" -eq 0 ]
  ! grep -q '# label: target' "$WG_ROOT/etc/wireguard/wg0.conf"
  grep -q '# label: standalone-comment' "$WG_ROOT/etc/wireguard/wg0.conf"
}
