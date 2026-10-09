#!/usr/bin/env bash
# Module 20 — create_user: create a non-root sudo user (spec §8.4).
# Config: NEW_USERNAME, NEW_PASSWORD.
#
# Root SSH is NEVER disabled here: this module runs detached and cannot
# prove the new login works (spec §10.2 step 3). The only root-disable path
# is the app-driven hardening flow (disable_root_ssh.sh) with the full
# anti-lockout harness.

run_create_user() {
  local username=${NEW_USERNAME:?NEW_USERNAME is required}
  # Reject anything that is not a plain POSIX user name before it reaches a
  # command line (the rejected value is not echoed).
  if [[ ! $username =~ ^[a-z_][a-z0-9_-]*$ ]]; then
    log 'NEW_USERNAME is not a valid user name; aborting'
    return 1
  fi

  # Idempotent: a first run that died between useradd and the password/sudo
  # steps (or a pre-existing FAV account) must converge on re-run — don't
  # skip the password + sudo group just because the account exists (audit H8).
  if id "$username" &>/dev/null; then
    log "User ${username} already exists"
  else
    log "Creating user ${username}"
    useradd -m -s /bin/bash "$username"
  fi

  # usermod -aG is idempotent, so always ensure sudo membership.
  usermod -aG sudo "$username"

  # Set the password only when the account has no usable one yet (freshly
  # created, or a locked / passwordless pre-existing account). Never overwrite
  # a usable password an admin may already have set on a pre-existing user.
  local pw_status
  pw_status=$(passwd -S "$username" 2>/dev/null | awk '{print $2}')
  if [[ $pw_status == L || $pw_status == NP || -z $pw_status ]]; then
    # The password is piped via stdin so it never appears in the process list.
    printf '%s:%s' "$username" "${NEW_PASSWORD:?NEW_PASSWORD is required}" |
      chpasswd
  else
    log "User ${username} already has a password; leaving it unchanged"
  fi
}
