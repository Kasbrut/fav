#!/usr/bin/env bash
# Module 10 — install_pkgs: install the WireGuard packages (spec §8.2).
# `sudo` is required for the new-user flow and the §10.2 anti-lockout
# sequence — Debian minimal/cloud templates may omit it.

run_install_pkgs() {
  export DEBIAN_FRONTEND=noninteractive
  log "Updating the package index"
  apt_get update -qq
  # QR codes are rendered in-app (qr_flutter); no server-side qrencode needed.
  log "Installing wireguard, wireguard-tools, iptables, sudo, python3, iproute2 and iputils-ping"
  apt_get install -y -qq wireguard wireguard-tools iptables sudo python3 iproute2 iputils-ping
  log "Packages installed"
}
