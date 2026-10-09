#!/usr/bin/env bash
# Disables root SSH login with anti-lockout safeguards (spec §10.2).
#
# Run as root — the app invokes it via `sudo -S bash` only after verifying,
# from a second SSH session, that the new non-root user can log in and use
# sudo (spec §10.2 steps 3-4). Validates a candidate sshd_config with
# `sshd -t`, backs it up with a timestamp, applies it, reloads, confirms sshd
# is still active, and rolls back on any anomaly. Prints `WG-LCK-OK` on
# success or `WG-LCK-ABORTED` on abort.
set -euo pipefail
IFS=$'\n\t'

# Prints a timestamped log line.
log() {
  printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"
}

# Reloads the SSH daemon, tolerating both the `ssh` and `sshd` unit names.
reload_sshd() {
  systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null
}

# Succeeds if the SSH daemon is currently active.
sshd_active() {
  systemctl is-active --quiet ssh 2>/dev/null ||
    systemctl is-active --quiet sshd 2>/dev/null
}

# Restores sshd_config from a backup and reloads.
rollback_sshd() {
  local config=$1 backup=$2
  cp -p "$backup" "$config"
  if reload_sshd && sshd_active; then
    log 'Rollback complete; root SSH login left enabled'
  else
    log 'CRITICAL: sshd rollback unconfirmed; check the server console'
  fi
}

# Succeeds if an sshd drop-in or Match block still permits root login.
#
# Any PermitRootLogin value other than `no` permits a root login —
# `prohibit-password` and `without-password` (common on cloud images) allow
# key-based root login, `forced-commands-only` allows it for forced commands.
root_still_permitted() {
  local config=$1
  local dropins=${config%/sshd_config}/sshd_config.d
  local permits='^[[:space:]]*PermitRootLogin[[:space:]]+'
  permits+='(yes|prohibit-password|without-password|forced-commands-only)'
  grep -rEl "$permits" "$config" "$dropins" 2>/dev/null | grep -q .
}

# Succeeds if sshd's EFFECTIVE configuration still permits a root login.
# `sshd -T` (without -C) reports the GLOBAL scope authoritatively, resolving
# drop-ins, Include files and compiled defaults — so any value other than `no`
# (including the `prohibit-password` default that applies when no directive is
# in scope) is caught here. Fails closed if the effective config is unreadable.
root_login_still_permitted() {
  local config=$1 effective
  effective=$(sshd -T -f "$config" 2>/dev/null) || return 0
  ! grep -qiE '^permitrootlogin[[:space:]]+no([[:space:]]|$)' <<<"$effective"
}

main() {
  # WG_ROOT is empty in production; tests set it to sandbox writes.
  local config=${WG_ROOT:-}/etc/ssh/sshd_config
  local stamp backup candidate
  stamp=$(date -u +%Y%m%d%H%M%S)
  backup="${config}.wg-installer.bak.${stamp}"
  candidate=$(mktemp)

  # Drop every PermitRootLogin line (commented or not, leading whitespace
  # tolerated, inside Match blocks too) and re-insert it once in the GLOBAL
  # scope — before the first Match block if present, otherwise at EOF. A
  # directive placed after `Match` is scoped to it and would not disable root
  # globally.
  local stripped
  stripped=$(mktemp)
  grep -Ev '^[[:space:]]*#?[[:space:]]*PermitRootLogin[[:space:]=]' "$config" \
    >"$stripped" || true
  awk '
    !inserted && $1 == "Match" { print "PermitRootLogin no"; inserted = 1 }
    { print }
    END { if (!inserted) print "PermitRootLogin no" }
  ' "$stripped" >"$candidate"
  rm -f "$stripped"
  if ! sshd -t -f "$candidate"; then
    log 'sshd config invalid; leaving root SSH enabled'
    rm -f "$candidate"
    printf 'WG-LCK-ABORTED\n'
    return 1
  fi

  cp -p "$config" "$backup"
  cp "$candidate" "$config"
  rm -f "$candidate"

  if ! reload_sshd; then
    log 'sshd reload failed; rolling back sshd_config'
    rollback_sshd "$config" "$backup"
    printf 'WG-LCK-ABORTED\n'
    return 1
  fi
  if ! sshd_active; then
    log 'sshd is not active after reload; rolling back sshd_config'
    rollback_sshd "$config" "$backup"
    printf 'WG-LCK-ABORTED\n'
    return 1
  fi
  # Verify the EFFECTIVE config: a Match block, Include or drop-in could leave
  # root login reachable even though the main file looks correct. Roll back
  # rather than report a change that did not take effect.
  if root_login_still_permitted "$config"; then
    log 'sshd still permits root login after the change (Match block, Include'
    log 'or drop-in override); rolling back sshd_config'
    rollback_sshd "$config" "$backup"
    printf 'WG-LCK-ABORTED\n'
    return 1
  fi
  # Secondary guard: a drop-in or Match block that re-enables root login (also
  # covered by the check above on a host with `sshd -T`).
  if root_still_permitted "$config"; then
    log 'PermitRootLogin yes still present in an sshd drop-in;'
    log 'root SSH is NOT fully disabled'
    rollback_sshd "$config" "$backup"
    printf 'WG-LCK-ABORTED\n'
    return 1
  fi
  log 'Root SSH login disabled'
  printf 'WG-LCK-OK\n'
}

main
