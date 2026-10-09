#!/usr/bin/env bash
# Re-opens SSH access by undoing FAV's hardening (server teardown).
#
# Run as root — the app invokes it via `sudo -S bash` over a live session,
# exactly like disable_root_ssh.sh / disable_password_auth.sh. Restores the
# PermitRootLogin and PasswordAuthentication directives FAV changed, reading
# their pre-FAV values from the oldest FAV sshd_config backup when present and
# falling back to safe re-opening defaults otherwise. Validates the candidate
# with `sshd -t`, backs up the current config, applies it, reloads, confirms
# sshd is still active, and rolls back on any anomaly. Prints `WG-RVT-OK` on
# success or `WG-RVT-ABORTED` on abort.
set -euo pipefail
IFS=$'\n\t'

log() {
  printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"
}

reload_sshd() {
  systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null
}

sshd_active() {
  systemctl is-active --quiet ssh 2>/dev/null ||
    systemctl is-active --quiet sshd 2>/dev/null
}

rollback_sshd() {
  local config=$1 backup=$2
  cp -p "$backup" "$config"
  if reload_sshd && sshd_active; then
    log 'Rollback complete; SSH hardening left in place'
  else
    log 'CRITICAL: sshd rollback unconfirmed; check the server console'
  fi
}

# force_option <candidate> <option> <value>: remove every existing entry for
# <option> (commented or not, anywhere) and insert it once in the global scope,
# before the first Match block. Mirrors disable_password_auth.sh.
force_option() {
  local candidate=$1 option=$2 value=$3
  local stripped tmp
  stripped=$(mktemp)
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

# Succeeds when sshd's EFFECTIVE configuration reflects the re-opened
# values. `sshd -T` resolves drop-ins, Include files and compiled defaults
# authoritatively (global scope, Match rules not applied) — a drop-in still
# forcing `PasswordAuthentication no` would otherwise let WG-RVT-OK claim an
# access path that does not exist, and the app would then remove the FAV key
# trusting it (parity with the disable scripts). Fails closed when the
# effective config cannot be read.
reopen_effective() {
  local config=$1 root_val=$2 pass_val=$3 effective root_pattern
  effective=$(sshd -T -f "$config" 2>/dev/null) || return 1
  root_pattern=$root_val
  if [[ $root_val == prohibit-password || $root_val == without-password ]]; then
    root_pattern='(prohibit-password|without-password)'
  fi
  grep -qiE "^permitrootlogin[[:space:]]+${root_pattern}([[:space:]]|\$)" \
    <<<"$effective" || return 1
  grep -qiE "^passwordauthentication[[:space:]]+${pass_val}([[:space:]]|\$)" \
    <<<"$effective" || return 1
}

# oldest_backup <config>: echo the oldest FAV sshd backup (the pre-hardening
# original), or empty when none exists.
oldest_backup() {
  local config=$1
  ls -1 "${config}".wg-installer.bak.* 2>/dev/null | sort | head -1 || true
}

# prior_value <backup> <option> <default>: echo the value of <option> from the
# backup if present and not the hardened `no`, else <default>. Tokens are
# lowercased (a hardened `No` must count as `no` — else it would be restored
# verbatim under a WG-RVT-OK that still blocks passwords) and the deprecated
# `without-password` alias normalizes to `prohibit-password`, the only form
# `sshd -T` reports — the effective re-check compares against this output.
prior_value() {
  local backup=$1 option=$2 default=$3 found=''
  if [[ -n $backup && -f $backup ]]; then
    found=$(grep -iE "^[[:space:]]*${option}[[:space:]]+" "$backup" |
      tail -1 | awk '{print $2}' | tr '[:upper:]' '[:lower:]')
  fi
  if [[ $found == without-password ]]; then
    found='prohibit-password'
  fi
  if [[ -n $found && $found != no ]]; then
    printf '%s' "$found"
  else
    printf '%s' "$default"
  fi
}

main() {
  local config=${WG_ROOT:-}/etc/ssh/sshd_config
  if [[ ! -f $config ]]; then
    log 'sshd_config not found; nothing to re-open'
    printf 'WG-RVT-ABORTED\n'
    return 1
  fi

  local backup_src root_val pass_val
  backup_src=$(oldest_backup "$config")
  root_val=$(prior_value "$backup_src" 'PermitRootLogin' 'prohibit-password')
  pass_val=$(prior_value "$backup_src" 'PasswordAuthentication' 'yes')

  local candidate
  candidate=$(mktemp)
  cp "$config" "$candidate"
  force_option "$candidate" 'PermitRootLogin' "$root_val"
  force_option "$candidate" 'PasswordAuthentication' "$pass_val"
  force_option "$candidate" 'KbdInteractiveAuthentication' "$pass_val"

  if ! sshd -t -f "$candidate"; then
    log 'candidate sshd config invalid; leaving hardening in place'
    rm -f "$candidate"
    printf 'WG-RVT-ABORTED\n'
    return 1
  fi

  local stamp backup
  stamp=$(date -u +%Y%m%d%H%M%S)
  backup="${config}.wg-installer.bak.${stamp}"
  cp -p "$config" "$backup"
  cp "$candidate" "$config"
  rm -f "$candidate"

  if ! reload_sshd; then
    log 'sshd reload failed; rolling back'
    rollback_sshd "$config" "$backup"
    printf 'WG-RVT-ABORTED\n'
    return 1
  fi
  if ! sshd_active; then
    log 'sshd not active after reload; rolling back'
    rollback_sshd "$config" "$backup"
    printf 'WG-RVT-ABORTED\n'
    return 1
  fi
  if ! reopen_effective "$config" "$root_val" "$pass_val"; then
    log 'effective sshd config does not reflect the re-open; rolling back'
    rollback_sshd "$config" "$backup"
    printf 'WG-RVT-ABORTED\n'
    return 1
  fi

  log "Re-opened SSH (PermitRootLogin ${root_val}, PasswordAuthentication ${pass_val})"
  printf 'WG-RVT-OK\n'
}

main "$@"
