#!/usr/bin/env bash
# Module 15 — validate the v2 request and discover IPv6 capability. The Python
# helper owns all temporary namespace, veth, route and probe-rule cleanup.

run_network_probe() {
  if [[ ${FAV_CONFIG_VERSION:-} != 2 ]]; then
    log 'ERR-NET-VERSION-UNSUPPORTED'
    return 42
  fi
  export NETWORK_RESULT_PATH="$RUN_DIR/network-result.json"
  if ! python3 "$RUN_DIR/lib/network_probe.py"; then
    log 'ERR-NET-CONFIG-INVALID'
    return 42
  fi
  log 'IPv6 capability result recorded'
}
