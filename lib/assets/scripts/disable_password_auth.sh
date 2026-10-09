#!/usr/bin/env bash
# Disables SSH password authentication with anti-lockout safeguards
# (spec §10.3).
#
# Run as root — the app invokes it via `sudo -S bash` only after verifying,
# from a separate key-based SSH session, that the new non-root user can log
# in with the app-generated Ed25519 key (spec §10.3). Validates a candidate
# sshd_config with `sshd -t`, backs it up with a timestamp, applies it,
# reloads, confirms sshd is still active, and rolls back on any anomaly.
# Prints `WG-HRD-OK` on success or `WG-HRD-ABORTED` on abort.
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
    log 'Rollback complete; password authentication left enabled'
  else
    log 'CRITICAL: sshd rollback unconfirmed; check the server console'
  fi
}

# Forces an `Option value` line in $candidate in the GLOBAL scope: removes
# every existing entry (commented or not, anywhere — including inside Match
# blocks) and re-inserts the desired one once. The line is placed before the
# first Match block if one exists; a directive that lands after `Match` is
# scoped to it and would NOT take effect globally, silently leaving the option
# at its inherited default.
force_option() {
  local candidate=$1 option=$2 value=$3
  local stripped tmp
  stripped=$(mktemp)
  # Drop every line that sets this option (commented or not, leading
  # whitespace tolerated, `key value` or `key=value` form). Case is preserved
  # by sshd, but the canonical form uses the exact spelling above.
  grep -Ev "^[[:space:]]*#?[[:space:]]*${option}[[:space:]=]" "$candidate" \
    >"$stripped" || true
  tmp=$(mktemp)
  awk -v opt="$option" -v val="$value" '
    !inserted && $1 == "Match" { print opt, val; inserted = 1 }
    { print }
    END { if (!inserted) print opt, val }
  ' "$stripped" >"$tmp"
  rm -f "$stripped"
  mv "$tmp" "$candidate"
}

# Succeeds if sshd's EFFECTIVE configuration still accepts password logins.
# `sshd -T` resolves drop-ins, Include files, Match blocks and compiled
# defaults authoritatively, and without -C it reports the GLOBAL scope (Match
# rules are not applied) — catching a directive mis-scoped into a Match block
# or overridden elsewhere, which a plain text grep of the main file misses.
# Fails closed: if the effective config cannot be read, treat it as unsafe.
password_auth_still_enabled() {
  local config=$1 effective
  effective=$(sshd -T -f "$config" 2>/dev/null) || return 0
  if ! grep -qiE '^passwordauthentication[[:space:]]+no([[:space:]]|$)' \
    <<<"$effective"; then
    return 0
  fi
  if grep -qiE '^kbdinteractiveauthentication[[:space:]]+yes([[:space:]]|$)' \
    <<<"$effective"; then
    return 0
  fi
  return 1
}

# Succeeds if a drop-in file under sshd_config.d still re-enables password
# authentication: those override the main file and would silently undo the
# change. Kept as a secondary guard alongside the authoritative `sshd -T`
# check above.
password_auth_overridden() {
  local config=$1
  local dropins=${config%/sshd_config}/sshd_config.d
  local re='^[[:space:]]*PasswordAuthentication[[:space:]]+yes'
  grep -rEl "$re" "$dropins" 2>/dev/null | grep -q .
}

main() {
  # WG_ROOT is empty in production; tests set it to sandbox writes.
  local config=${WG_ROOT:-}/etc/ssh/sshd_config
  local stamp backup candidate
  stamp=$(date -u +%Y%m%d%H%M%S)
  backup="${config}.wg-installer.bak.${stamp}"
  candidate=$(mktemp)

  cp "$config" "$candidate"
  # Three settings together actually disable password-based login on modern
  # sshd: PasswordAuthentication blocks the plain prompt, PubkeyAuthentication
  # keeps the key path alive, KbdInteractiveAuthentication blocks the PAM
  # keyboard-interactive bypass (modern sshd dropped the legacy
  # ChallengeResponseAuthentication name in favour of this one).
  force_option "$candidate" 'PasswordAuthentication' 'no'
  force_option "$candidate" 'PubkeyAuthentication' 'yes'
  force_option "$candidate" 'KbdInteractiveAuthentication' 'no'

  if ! sshd -t -f "$candidate"; then
    log 'sshd config invalid; leaving password authentication enabled'
    rm -f "$candidate"
    printf 'WG-HRD-ABORTED\n'
    return 1
  fi

  cp -p "$config" "$backup"
  cp "$candidate" "$config"
  rm -f "$candidate"

  if ! reload_sshd; then
    log 'sshd reload failed; rolling back sshd_config'
    rollback_sshd "$config" "$backup"
    printf 'WG-HRD-ABORTED\n'
    return 1
  fi
  if ! sshd_active; then
    log 'sshd is not active after reload; rolling back sshd_config'
    rollback_sshd "$config" "$backup"
    printf 'WG-HRD-ABORTED\n'
    return 1
  fi
  # Verify the EFFECTIVE config: a Match block, Include or drop-in could leave
  # password logins enabled even though the main file looks correct. Roll back
  # rather than report a hardening that did not take effect.
  if password_auth_still_enabled "$config"; then
    log 'sshd still accepts password logins after the change (Match block,'
    log 'Include or drop-in override); rolling back sshd_config'
    rollback_sshd "$config" "$backup"
    printf 'WG-HRD-ABORTED\n'
    return 1
  fi
  # Secondary guard: a drop-in file under sshd_config.d that re-enables
  # password auth (also covered by the check above on a host with `sshd -T`).
  if password_auth_overridden "$config"; then
    log 'PasswordAuthentication yes still present in an sshd drop-in;'
    log 'password authentication is NOT fully disabled'
    rollback_sshd "$config" "$backup"
    printf 'WG-HRD-ABORTED\n'
    return 1
  fi
  log 'SSH password authentication disabled'
  printf 'WG-HRD-OK\n'
}

main
