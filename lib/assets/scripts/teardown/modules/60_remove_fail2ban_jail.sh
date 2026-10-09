#!/usr/bin/env bash
# Teardown 60 — remove_fail2ban_jail: remove the SSH jail FAV wrote
# (spec §10.3). Idempotent. The fail2ban package is deliberately left
# installed — it may be used beyond FAV.

run_remove_fail2ban_jail() {
  local jail=${WG_ROOT:-}/etc/fail2ban/jail.d/sshd.local
  if [[ -e $jail ]]; then
    rm -f "$jail"
    log "Removed ${jail}"
    systemctl reload fail2ban 2>/dev/null || true
  else
    log 'fail2ban jail not present, skipping'
  fi
}
