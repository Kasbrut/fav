#!/usr/bin/env python3
"""Validate a v2 request and emit its authoritative IPv6 capability result."""

import datetime
import hashlib
import ipaddress
import json
import os
import re
import subprocess
import sys
import tempfile


class ProbeError(Exception):
    pass


INELIGIBLE_ROUTED_RANGES = tuple(
    ipaddress.ip_network(value)
    for value in ("2001::/32", "2001:db8::/32", "2002::/16", "64:ff9b::/96")
)
PROC_ROOT = os.environ.get("FAV_PROC_ROOT", "/proc")


def run(*args, check=True):
    result = subprocess.run(args, text=True, capture_output=True, timeout=10)
    if check and result.returncode != 0:
        raise ProbeError("command_failed")
    return result


def route_device(family):
    result = run("ip", f"-{family}", "route", "show", "default", check=False)
    if result.returncode != 0:
        return None
    for line in result.stdout.splitlines():
        fields = line.split()
        if "dev" in fields:
            index = fields.index("dev")
            if index + 1 < len(fields):
                return fields[index + 1]
    return None


def backend(command):
    result = run(command, "--version", check=False)
    if result.returncode != 0:
        raise ProbeError("firewall_command_missing")
    text = result.stdout + result.stderr
    if "nf_tables" in text:
        return "nf_tables"
    if "legacy" in text:
        return "legacy"
    raise ProbeError("firewall_backend_unknown")


def env_token(name):
    value = os.environ.get(name, "")
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._:-]{0,127}", value):
        raise ProbeError("invalid_identity")
    return value


def network(name, required=True):
    value = os.environ.get(name, "")
    if not value and not required:
        return None
    try:
        parsed = ipaddress.ip_network(value, strict=True)
    except ValueError as error:
        raise ProbeError("invalid_ipv6_subnet") from error
    if parsed.version != 6 or parsed.prefixlen != 64:
        raise ProbeError("invalid_ipv6_subnet")
    return parsed


def add_address(prefix, slot):
    return ipaddress.IPv6Address(int(prefix.network_address) + slot)


def atomic_json(path, value):
    directory = os.path.dirname(path)
    fd, temporary = tempfile.mkstemp(prefix=".network-result.", dir=directory)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as output:
            json.dump(value, output, separators=(",", ":"), sort_keys=True)
            output.write("\n")
            output.flush()
            os.fsync(output.fileno())
        os.chmod(temporary, 0o600)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def main():
    if os.environ.get("FAV_CONFIG_VERSION") != "2":
        raise ProbeError("unsupported_version")
    installation = env_token("FAV_INSTALLATION_ID")
    operation = env_token("FAV_OPERATION_ID")
    ula = network("VPN_IPV6_ULA_SUBNET")
    if not ula.is_private or ula.network_address.packed[0] != 0xFD:
        raise ProbeError("invalid_ula_subnet")
    routed = network("VPN_IPV6_ROUTED_SUBNET", required=False)
    if routed is not None and (
        not routed.is_global
        or routed.is_private
        or any(routed.overlaps(blocked) for blocked in INELIGIBLE_ROUTED_RANGES)
    ):
        raise ProbeError("ineligible_routed_subnet")
    target_text = os.environ.get("IPV6_PROBE_TARGET", "")
    try:
        target = ipaddress.ip_address(target_text) if target_text else None
    except ValueError as error:
        raise ProbeError("invalid_probe_target") from error
    if target is not None and (target.version != 6 or not target.is_global):
        raise ProbeError("invalid_probe_target")

    disabled = open(
        os.path.join(PROC_ROOT, "sys/net/ipv6/conf/all/disable_ipv6"),
        encoding="ascii",
    ).read().strip()
    if disabled == "1":
        raise ProbeError("local_ipv6_disabled")
    if backend("iptables") != backend("ip6tables"):
        raise ProbeError("firewall_backend_mismatch")

    wan4 = route_device(4)
    wan6 = route_device(6)
    if wan4 is None:
        raise ProbeError("ipv4_default_route_missing")
    token = hashlib.sha256(operation.encode()).hexdigest()[:8]
    namespace = f"favp-{token}"
    host_link = f"fvh{token[:8]}"[:15]
    peer_link = f"fvn{token[:8]}"[:15]
    created_namespace = False
    created_link = False
    rules = []
    status = "unavailable"
    reason = "no_delegated_prefix"
    effective = ula
    try:
        if run("ip", "netns", "list", check=False).stdout.split() and namespace in run("ip", "netns", "list", check=False).stdout.split():
            raise ProbeError("probe_resource_conflict")
        if run("ip", "link", "show", "dev", host_link, check=False).returncode == 0:
            raise ProbeError("probe_resource_conflict")
        run("ip", "netns", "add", namespace)
        created_namespace = True
        run("ip", "link", "add", host_link, "type", "veth", "peer", "name", peer_link)
        created_link = True
        run("ip", "link", "set", peer_link, "netns", namespace)
        host_addr = add_address(ula, (1 << 64) - 3)
        peer_addr = add_address(ula, (1 << 64) - 4)
        run("ip", "addr", "add", f"{host_addr}/64", "dev", host_link)
        run("ip", "link", "set", host_link, "up")
        run("ip", "-n", namespace, "link", "set", "lo", "up")
        run("ip", "-n", namespace, "addr", "add", f"{peer_addr}/64", "dev", peer_link)
        run("ip", "-n", namespace, "link", "set", peer_link, "up")

        if routed is not None:
            effective = routed
            if wan6 is None:
                status, reason = "unavailable", "no_ipv6_default_route"
            elif target is None:
                status, reason = "unknown", "probe_target_missing"
            else:
                forwarding = open(
                    os.path.join(PROC_ROOT, "sys/net/ipv6/conf/all/forwarding"),
                    encoding="ascii",
                ).read().strip()
                if forwarding != "1":
                    status, reason = "unknown", "ipv6_forwarding_disabled"
                else:
                    source = add_address(routed, (1 << 64) - 2)
                    run("ip", "-n", namespace, "addr", "add", f"{source}/128", "dev", "lo")
                    run("ip", "-n", namespace, "-6", "route", "add", "default", "via", str(host_addr), "dev", peer_link)
                    run("ip", "-6", "route", "add", f"{source}/128", "dev", host_link)
                    comment = f"fav-probe-{token}"
                    outbound = ["ip6tables", "-I", "FORWARD", "1", "-i", host_link, "-o", wan6, "-s", f"{source}/128", "-d", f"{target}/128", "-m", "comment", "--comment", comment, "-j", "ACCEPT"]
                    inbound = ["ip6tables", "-I", "FORWARD", "1", "-i", wan6, "-o", host_link, "-s", f"{target}/128", "-d", f"{source}/128", "-m", "comment", "--comment", comment, "-j", "ACCEPT"]
                    for rule in (outbound, inbound):
                        run(*rule)
                        rules.append(rule)
                    reply = run("ip", "netns", "exec", namespace, "ping", "-6", "-n", "-c", "1", "-W", "3", "-I", str(source), str(target), check=False)
                    if reply.returncode == 0 and ("1 received" in reply.stdout or "1 packets received" in reply.stdout):
                        status, reason = "supported", "return_path_verified"
                    elif reply.returncode == 0:
                        status, reason = "unknown", "probe_reply_mismatch"
                    else:
                        status, reason = "unknown", "probe_timeout"
    finally:
        for rule in reversed(rules):
            delete = rule[:]
            delete[1] = "-D"
            del delete[3]
            run(*delete, check=False)
        if created_link:
            run("ip", "link", "delete", host_link, check=False)
        if created_namespace:
            run("ip", "netns", "delete", namespace, check=False)

    if status != "supported":
        effective = ula
    result = {
        "schemaVersion": 2,
        "installationId": installation,
        "operationId": operation,
        "revision": 1,
        "network": {
            "ipv4Subnet": os.environ["VPN_SUBNET"],
            "ipv6Mode": "routed" if status == "supported" else "blocked",
            "ipv6Subnet": str(effective),
            "fallbackIpv6Subnet": str(ula),
            "serverIpv6Address": f"{add_address(effective, 1)}/64",
            "wan4": wan4,
            "wan6": wan6,
        },
        "capability": {
            "status": status,
            "reason": reason,
            "checkedAt": datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z"),
        },
    }
    atomic_json(os.environ["NETWORK_RESULT_PATH"], result)


if __name__ == "__main__":
    try:
        main()
    except (ProbeError, KeyError, OSError, subprocess.SubprocessError) as error:
        reason = str(error)
        if reason == "local_ipv6_disabled":
            token = "ERR-NET-IPV6-LOCAL-UNAVAILABLE"
        elif reason.startswith("firewall_"):
            token = "ERR-NET-FIREWALL-UNSUPPORTED"
        elif reason == "ipv4_default_route_missing":
            token = "ERR-NET-IPV4-UNAVAILABLE"
        else:
            token = "ERR-NET-CONFIG-INVALID"
        print(f"{token}:{reason}", file=sys.stderr)
        sys.exit(42)
