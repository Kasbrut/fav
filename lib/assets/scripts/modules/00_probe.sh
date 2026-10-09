#!/usr/bin/env bash
# Module 00 — probe: confirm the server runs a supported distribution and a
# kernel recent enough for WireGuard (spec §3.2, §8.2).

run_probe() {
  local os_id="" os_version="" kernel
  # OS_RELEASE_FILE defaults to the real path; tests point it at a fixture.
  local osr=${OS_RELEASE_FILE:-/etc/os-release}
  if [[ -r $osr ]]; then
    # shellcheck disable=SC1090
    os_id=$(. "$osr" && printf '%s' "${ID:-}")
    # shellcheck disable=SC1090
    os_version=$(. "$osr" && printf '%s' "${VERSION_ID:-}")
  fi
  kernel=$(uname -r)
  log "OS: ${os_id} ${os_version} | kernel: ${kernel}"

  case $os_id in
    debian | ubuntu) ;;
    *)
      log "Unsupported distribution '${os_id}' (Debian or Ubuntu required)"
      return 1
      ;;
  esac

  local major minor
  major=${kernel%%.*}
  minor=${kernel#*.}
  minor=${minor%%.*}
  if [[ ! $major =~ ^[0-9]+$ || ! $minor =~ ^[0-9]+$ ]]; then
    log "Cannot parse kernel version '${kernel}'"
    return 1
  fi
  if (( major < 5 || (major == 5 && minor < 6) )); then
    log "Kernel ${kernel} is too old for WireGuard (5.6 or newer required)"
    return 1
  fi
}
