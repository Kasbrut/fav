#!/usr/bin/env bash
# Shared helpers for the WireGuard installer.
#
# Provides a pure-bash state machine that writes the run state file in the
# format of spec §7.4 — no external dependency such as `jq`, so it works on a
# bare server. The orchestrator sets RUN_ID, STATE_FILE and EXIT_FILE before
# sourcing this file.

# shellcheck disable=SC2034  # consumed by the orchestrator and the modules.
# Ordered list of installation step keys (one per numbered module).
STEP_KEYS=(
  probe
  install_pkgs
  create_user
  deploy_app_key
  deploy_user_keys
  generate_keys
  write_server_conf
  firewall_guard
  enable_forwarding
  firewall
  start_service
  hardening
  health_check
  finalize
)

declare -A STEP_STATUS
declare -A STEP_STARTED
declare -A STEP_ENDED

RUN_STARTED_AT=""
CURRENT_STEP="init"
CURRENT_STEP_STARTED_AT=""
RUN_ERROR=""

# Prints the current UTC time in ISO-8601 form.
now_iso() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}

# Escapes a string for safe inclusion in a JSON double-quoted value: escapes
# backslash and double quote, and folds every control character (newline, tab,
# etc.) to a space — JSON forbids raw control characters in string values.
json_escape() {
  local value=$1
  value=${value//\\/\\\\}
  value=${value//\"/\\\"}
  value=${value//[[:cntrl:]]/ }
  printf '%s' "$value"
}

# Logs a timestamped line to stdout (captured into the run log).
# Never pass secrets (passwords, private keys, PSKs) to this function.
log() {
  printf '[%s] %s\n' "$(now_iso)" "$*"
}

# Wraps `apt-get` so concurrent dpkg holders (typically
# `apt-daily-upgrade.service` / `unattended-upgrades`, which systemd kicks
# off shortly after boot or after installing packages) release the lock
# instead of failing the run. `DPkg::Lock::Timeout` is honoured by every
# apt-get subcommand and is supported on Debian 11+ / Ubuntu 20.04+.
# 300s is generous: a default unattended-upgrades pass finishes well
# under that window on a fresh VM.
APT_LOCK_TIMEOUT=${APT_LOCK_TIMEOUT:-300}
apt_get() {
  apt-get -o DPkg::Lock::Timeout="$APT_LOCK_TIMEOUT" "$@"
}

# Regenerates the state file atomically from the in-memory step arrays.
write_state() {
  local tmp="${STATE_FILE}.tmp"
  local last=$(( ${#STEP_KEYS[@]} - 1 ))
  local index key
  {
    printf '{\n'
    printf '  "run_id": "%s",\n' "$(json_escape "$RUN_ID")"
    printf '  "started_at": "%s",\n' "$RUN_STARTED_AT"
    printf '  "current_step": "%s",\n' "$(json_escape "$CURRENT_STEP")"
    printf '  "current_step_started_at": "%s",\n' "$CURRENT_STEP_STARTED_AT"
    printf '  "steps": {\n'
    for index in "${!STEP_KEYS[@]}"; do
      key=${STEP_KEYS[$index]}
      printf '    "%s": {"status": "%s"' "$key" "${STEP_STATUS[$key]}"
      if [[ -n ${STEP_STARTED[$key]:-} ]]; then
        printf ', "started_at": "%s"' "${STEP_STARTED[$key]}"
      fi
      if [[ -n ${STEP_ENDED[$key]:-} ]]; then
        printf ', "ended_at": "%s"' "${STEP_ENDED[$key]}"
      fi
      printf '}'
      if [[ $index -lt $last ]]; then
        printf ','
      fi
      printf '\n'
    done
    printf '  },\n'
    printf '  "warnings": [],\n'
    if [[ -n $RUN_ERROR ]]; then
      printf '  "error": "%s"\n' "$(json_escape "$RUN_ERROR")"
    else
      printf '  "error": null\n'
    fi
    printf '}\n'
  } >"$tmp"
  mv -f "$tmp" "$STATE_FILE"
}

# Initializes every step to "pending" and writes the first state file.
state_init() {
  RUN_STARTED_AT=$(now_iso)
  CURRENT_STEP="init"
  local key
  for key in "${STEP_KEYS[@]}"; do
    STEP_STATUS[$key]="pending"
  done
  write_state
}

# Marks a step's status and rewrites the state file.
# Usage: set_step <key> <running|done|error|skipped> [error-message]
# The error message is written verbatim into state.json: pass only fixed
# identifiers, never variable content or secrets (see the log() note).
set_step() {
  local key=$1
  local status=$2
  local message=${3:-}
  STEP_STATUS[$key]=$status
  case $status in
    running)
      CURRENT_STEP=$key
      CURRENT_STEP_STARTED_AT=$(now_iso)
      STEP_STARTED[$key]=$CURRENT_STEP_STARTED_AT
      ;;
    done | error | skipped)
      STEP_ENDED[$key]=$(now_iso)
      ;;
    *) ;;
  esac
  if [[ -n $message ]]; then
    RUN_ERROR=$message
  fi
  write_state
}

# Appends an OpenSSH public key to ~user/.ssh/authorized_keys unless it is
# already present (idempotent re-run). Creates .ssh/ if needed; directory and
# file modes match the defaults sshd enforces (0700 / 0600), owned by the
# target user. Shared by `25_deploy_app_key` (app key) and `26_deploy_user_keys`
# (user-supplied keys). Never pass secrets here — public keys only.
# Usage: deploy_authorized_key <username> <public-key-line>
deploy_authorized_key() {
  local username=$1 pubkey=$2
  local home ssh_dir keys_file
  home=$(getent passwd "$username" | cut -d: -f6)
  if [[ -z $home ]]; then
    log "User ${username} has no home directory; aborting"
    return 1
  fi
  ssh_dir="$home/.ssh"
  keys_file="$ssh_dir/authorized_keys"
  mkdir -p "$ssh_dir"
  chmod 700 "$ssh_dir"
  chown "$username":"$username" "$ssh_dir"
  touch "$keys_file"
  if grep -qxF -- "$pubkey" "$keys_file"; then
    log "Public key already authorized for ${username}"
  else
    printf '%s\n' "$pubkey" >>"$keys_file"
    log "Public key authorized for ${username}"
  fi
  chmod 600 "$keys_file"
  chown "$username":"$username" "$keys_file"
}

# Prints the WAN interface of the default route, or `eth0` if it cannot be
# determined. Parses positionally by the `dev` keyword so it works both for a
# normal `default via GW dev IF ...` route and for a PPPoE / scope-link
# `default dev pppX ...` route where the interface is not field 5.
detect_default_wan() {
  local wan
  wan=$(ip route show default 2>/dev/null |
    awk '{for (i = 1; i < NF; i++) if ($i == "dev") { print $(i + 1); exit }}')
  printf '%s\n' "${wan:-eth0}"
}

# EXIT-trap handler: records the final exit code for the polling app and, on
# failure, marks the step that was still running as errored.
on_installer_exit() {
  local code=$?
  printf '%s\n' "$code" >"$EXIT_FILE"
  if [[ $code -ne 0 && -n $CURRENT_STEP &&
    ${STEP_STATUS[$CURRENT_STEP]:-} == running ]]; then
    set_step "$CURRENT_STEP" "error" "step ${CURRENT_STEP} failed (exit ${code})"
  fi
}
