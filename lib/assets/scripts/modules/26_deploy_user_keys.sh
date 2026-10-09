#!/usr/bin/env bash
# Module 26 — deploy_user_keys: append the user-supplied SSH public keys to the
# management user's authorized_keys, so an advanced user keeps their own
# interactive access after the optional hardening disables password login.
# Complements `25_deploy_app_key.sh` (the app's own key) and reuses its shared
# `deploy_authorized_key` helper from lib/common.sh.
#
# Config:
#   - USER_AUTHORIZED_KEYS_B64 (required: base64 of the newline-joined OpenSSH
#     `authorized_keys` lines — base64 because config.env forbids newlines)
#   - NEW_USERNAME (optional — defaults to `root` when no new user is created)
#
# The orchestrator skips this step when USER_AUTHORIZED_KEYS_B64 is unset/empty.

# Accepted OpenSSH key types (kept in sync with SshPublicKey.types in the app).
_USER_KEY_TYPES=(
  ssh-ed25519
  ssh-rsa
  ecdsa-sha2-nistp256
  ecdsa-sha2-nistp384
  ecdsa-sha2-nistp521
  sk-ssh-ed25519@openssh.com
  sk-ecdsa-sha2-nistp256@openssh.com
)

run_deploy_user_keys() {
  if [[ -z ${USER_AUTHORIZED_KEYS_B64:-} ]]; then
    log 'USER_AUTHORIZED_KEYS_B64 is empty; nothing to deploy'
    return 0
  fi

  local username=${NEW_USERNAME:-root}
  if [[ ! ${username} =~ ^[a-z_][a-z0-9_-]*$ ]]; then
    log 'NEW_USERNAME is not a valid user name; aborting'
    return 1
  fi

  local decoded
  if ! decoded=$(printf '%s' "$USER_AUTHORIZED_KEYS_B64" | base64 -d 2>/dev/null); then
    log 'USER_AUTHORIZED_KEYS_B64 is not valid base64; aborting'
    return 1
  fi

  local line
  while IFS= read -r line; do
    [[ -z $line ]] && continue
    if ! _is_accepted_key_type "$line"; then
      log 'Skipping a user key with an unrecognized type'
      continue
    fi
    deploy_authorized_key "$username" "$line"
  done <<<"$decoded"
}

# Whether the key line starts with one of the accepted type prefixes followed
# by a space. Defense in depth — the app validates first.
_is_accepted_key_type() {
  local line=$1 type
  for type in "${_USER_KEY_TYPES[@]}"; do
    if [[ $line == "$type "* ]]; then
      return 0
    fi
  done
  return 1
}
