#!/usr/bin/env bash
# Module 25 — deploy_app_key: append the app-generated Ed25519 public key to
# the login user's authorized_keys, unconditionally for every installation
# (M15-T1). Splits the key-deployment responsibility out of `80_hardening.sh`
# so that post-install operations (monitoring, run recovery, future client
# CRUD) can authenticate by key even when SSH hardening is disabled.
#
# Config:
#   - SSH_PUBKEY (required, OpenSSH `ssh-ed25519 BASE64 [comment]`)
#   - NEW_USERNAME (optional — defaults to `root` when no new user is created)
#
# The orchestrator skips this step when SSH_PUBKEY is unset so the BATS suite,
# and any operator running the orchestrator standalone, keep working.

run_deploy_app_key() {
  if [[ -z ${SSH_PUBKEY:-} ]]; then
    log 'SSH_PUBKEY is required; aborting'
    return 1
  fi
  # The public key must be a single line in OpenSSH authorized_keys form
  # (`ssh-ed25519 BASE64 [comment]`). Rejecting embedded newlines here keeps
  # authorized_keys to one entry per logical key.
  if [[ ${SSH_PUBKEY} == *$'\n'* ]]; then
    log 'SSH_PUBKEY must not contain newlines; aborting'
    return 1
  fi
  if [[ ${SSH_PUBKEY} != 'ssh-ed25519 '* ]]; then
    log 'SSH_PUBKEY must start with "ssh-ed25519 "; aborting'
    return 1
  fi

  local username=${NEW_USERNAME:-root}
  if [[ ! ${username} =~ ^[a-z_][a-z0-9_-]*$ ]]; then
    log 'NEW_USERNAME is not a valid user name; aborting'
    return 1
  fi

  # `deploy_authorized_key` is shared with `26_deploy_user_keys` via common.sh.
  deploy_authorized_key "$username" "$SSH_PUBKEY"
}
