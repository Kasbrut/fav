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
# blocks) and prepends the desired one before all Include/Match directives.
# An included file may itself leave the parser inside a Match block.
force_option() {
  local candidate=$1 option=$2 value=$3
  local stripped tmp
  stripped=$(mktemp)
  # Drop every line that sets this option (commented or not, leading
  # whitespace tolerated, `key value` or `key=value` form, any keyword case).
  grep -Eiv "^[[:space:]]*#?[[:space:]]*${option}[[:space:]=]" "$candidate" \
    >"$stripped" || true
  tmp=$(mktemp)
  awk -v opt="$option" -v val="$value" '
    BEGIN { print opt, val }
    { print }
  ' "$stripped" >"$tmp"
  rm -f "$stripped"
  mv "$tmp" "$candidate"
}

# Succeeds if sshd's effective GLOBAL configuration accepts password logins.
# `sshd -T` resolves global Include files and compiled
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
  if ! grep -qiE '^kbdinteractiveauthentication[[:space:]]+no([[:space:]]|$)' \
    <<<"$effective"; then
    return 0
  fi
  return 1
}

# Audit every reachable Include, regardless of Match conditions. A global
# sshd -T cannot prove that all users/addresses are safe. Reject any permissive
# directive even if an earlier value might override it; do not sample users.
# Relative Include paths are rooted at /etc/ssh (not the including file).
# Only unquoted paths are resolved here. Ambiguous quoting/escaping, unreadable
# files and excessive recursion fail closed. No config text is evaluated.
included_policy_safe() {
  local config=$1 policy=$2 depth=${3:-0}
  local line key value pattern included
  local -a patterns
  (( depth < 16 )) && [[ -f $config && -r $config ]] || return 1
  while IFS= read -r line || [[ -n $line ]]; do
    [[ $line =~ ^[[:space:]]*(#.*)?$ ]] && continue
    [[ $line =~ ^[[:space:]]*([[:alnum:]]+)[[:space:]=]+(.*)$ ]] || return 1
    key=${BASH_REMATCH[1],,}
    value=${BASH_REMATCH[2]}
    # A value separator may be written "Option = value".
    value=${value#=}
    value=${value%%[[:space:]]#*}
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    if [[ $key == include ]]; then
      [[ -n $value && $value != *\"* && $value != *"'"* &&
         $value != *\\* && $value != *'#'* && $value != *'$'* &&
         $value != *'~'* ]] || return 1
      IFS=$' \t' read -r -a patterns <<<"$value"
      for pattern in "${patterns[@]}"; do
        [[ $pattern == /* ]] || pattern="${WG_ROOT:-}/etc/ssh/$pattern"
        # compgen expands globs without evaluating shell substitutions.
        while IFS= read -r included; do
          included_policy_safe "$included" "$policy" "$((depth + 1))" || return 1
        done < <(compgen -G "$pattern" || true)
      done
    elif [[ $policy == password ]]; then
      case $key in
        passwordauthentication|kbdinteractiveauthentication|challengeresponseauthentication)
          [[ ${value,,} == no ]] || return 1 ;;
        pubkeyauthentication)
          [[ ${value,,} == yes ]] || return 1 ;;
      esac
    elif [[ $key == permitrootlogin ]]; then
      [[ ${value,,} == no ]] || return 1
    fi
  done <"$config"
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
  # keyboard-interactive bypass. The legacy alias is also normalized.
  force_option "$candidate" 'PasswordAuthentication' 'no'
  force_option "$candidate" 'PubkeyAuthentication' 'yes'
  force_option "$candidate" 'KbdInteractiveAuthentication' 'no'
  force_option "$candidate" 'ChallengeResponseAuthentication' 'no'

  if ! sshd -t -f "$candidate"; then
    log 'sshd config invalid; leaving password authentication enabled'
    rm -f "$candidate"
    printf 'WG-HRD-ABORTED\n'
    return 1
  fi

  if ! included_policy_safe "$candidate" password; then
    log 'Cannot prove all SSH Include/Match rules disable password authentication'
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
  if password_auth_still_enabled "$config" || ! included_policy_safe "$config" password; then
    log 'sshd still accepts password logins after the change (Match block,'
    log 'Include or drop-in override); rolling back sshd_config'
    rollback_sshd "$config" "$backup"
    printf 'WG-HRD-ABORTED\n'
    return 1
  fi
  log 'SSH password authentication disabled'
  printf 'WG-HRD-OK\n'
}

main
