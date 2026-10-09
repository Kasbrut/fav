#!/usr/bin/env python3
"""Owned, manifest-backed firewall/sysctl lifecycle for FAV v2 installs."""
import argparse
import glob
import ipaddress
import json
import os
import re
import stat
import subprocess
import tempfile


class FirewallError(Exception):
    pass


IFACE = re.compile(r"^[a-z_][a-z0-9_-]{0,14}$")
WAN = re.compile(r"^[A-Za-z0-9_.:-]{1,15}$")
IDENTITY = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$")


def run(argv, check=True):
    return subprocess.run(argv, check=check, text=True, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE)


def secure_json(path, expected_interface=None):
    if os.path.islink(path):
        raise FirewallError("unsafe_manifest")
    info = os.stat(path)
    if info.st_uid != os.geteuid() or stat.S_IMODE(info.st_mode) & 0o077:
        raise FirewallError("unsafe_manifest")
    with open(path, encoding="utf-8") as source:
        data = json.load(source)
    required = {"schemaVersion", "installationId", "revision", "state",
                "interfaceName", "network", "resources", "peers"}
    if not required <= data.keys() or data["schemaVersion"] != 2:
        raise FirewallError("invalid_manifest")
    iface = data["interfaceName"]
    if not isinstance(iface, str) or not IFACE.fullmatch(iface):
        raise FirewallError("invalid_interface")
    if expected_interface and iface != expected_interface:
        raise FirewallError("interface_mismatch")
    if os.path.basename(os.path.dirname(os.path.abspath(path))) != iface:
        raise FirewallError("interface_mismatch")
    if data["state"] != "ready":
        raise FirewallError("invalid_state")
    if (not isinstance(data["installationId"], str)
            or not IDENTITY.fullmatch(data["installationId"])):
        raise FirewallError("invalid_identity")
    if not isinstance(data["revision"], int) or data["revision"] < 1:
        raise FirewallError("invalid_revision")
    if not isinstance(data["resources"], dict):
        raise FirewallError("invalid_resources")
    return data


def atomic(path, data):
    directory = os.path.dirname(path)
    os.makedirs(directory, mode=0o700, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=".fav-firewall.", dir=directory)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as output:
            json.dump(data, output, separators=(",", ":"), sort_keys=True)
            output.write("\n")
            output.flush()
            os.fsync(output.fileno())
        os.chmod(temporary, 0o600)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def validate_network(data):
    network = data["network"]
    if not isinstance(network, dict):
        raise FirewallError("invalid_network")
    mode = network.get("ipv6Mode")
    if mode not in ("routed", "blocked"):
        raise FirewallError("invalid_mode")
    ipv4 = ipaddress.ip_network(network.get("ipv4Subnet", ""), strict=True)
    ipv6 = ipaddress.ip_network(network.get("ipv6Subnet", ""), strict=True)
    if ipv4.version != 4 or ipv4.prefixlen != 24 or ipv6.version != 6 or ipv6.prefixlen != 64:
        raise FirewallError("invalid_subnet")
    wan4, wan6 = network.get("wan4"), network.get("wan6")
    ssh_port = network.get("managementSshPort")
    if not isinstance(wan4, str) or not WAN.fullmatch(wan4):
        raise FirewallError("invalid_wan4")
    if mode == "routed" and (not isinstance(wan6, str) or not WAN.fullmatch(wan6)):
        raise FirewallError("invalid_wan6")
    if mode == "blocked" and wan6 is not None:
        raise FirewallError("unexpected_wan6")
    if type(ssh_port) is not int or not 1 <= ssh_port <= 65535:
        raise FirewallError("invalid_ssh_port")
    return mode, str(ipv4), str(ipv6), wan4, wan6, str(ssh_port)


def commands(data):
    mode, net4, net6, wan4, wan6, ssh_port = validate_network(data)
    iface = data["interfaceName"]
    tag = "fav:" + data["installationId"] + ":" + iface
    c4, c6, i4, i6 = "FAV4_" + iface, "FAV6_" + iface, "FAV4I_" + iface, "FAV6I_" + iface
    rules = []
    def add(binary, *args): rules.append([binary, *args])
    # Dedicated chains make ordering explicit and avoid broad host-chain rules.
    for binary, chain in (("iptables", c4), ("iptables", i4), ("ip6tables", c6), ("ip6tables", i6)):
        add(binary, "-N", chain)
    add("iptables", "-I", "FORWARD", "1", "-m", "comment", "--comment", tag, "-j", c4)
    add("iptables", "-I", "INPUT", "1", "-m", "comment", "--comment", tag, "-j", i4)
    add("ip6tables", "-I", "FORWARD", "1", "-m", "comment", "--comment", tag, "-j", c6)
    add("ip6tables", "-I", "INPUT", "1", "-m", "comment", "--comment", tag, "-j", i6)
    add("iptables", "-t", "nat", "-A", "POSTROUTING", "-s", net4, "-o", wan4,
        "-m", "comment", "--comment", tag, "-j", "MASQUERADE")
    add("iptables", "-A", c4, "-i", iface, "!", "-s", net4, "-j", "REJECT")
    add("iptables", "-A", c4, "-i", iface, "-o", iface, "-j", "REJECT")
    add("iptables", "-A", c4, "-i", iface, "-s", net4, "-o", wan4, "-j", "ACCEPT")
    add("iptables", "-A", c4, "-i", wan4, "-o", iface, "-d", net4, "-m", "conntrack", "--ctstate", "ESTABLISHED,RELATED", "-j", "ACCEPT")
    add("iptables", "-A", c4, "-i", wan4, "-o", iface, "-d", net4, "-j", "REJECT")
    add("iptables", "-A", i4, "-i", iface, "!", "-s", net4, "-j", "REJECT")
    add("iptables", "-A", i4, "-i", iface, "-s", net4, "-p", "tcp",
        "--dport", ssh_port, "-j", "ACCEPT")
    add("iptables", "-A", i4, "-i", iface, "-p", "icmp", "-j", "ACCEPT")
    add("iptables", "-A", i4, "-i", iface, "-j", "REJECT")
    add("ip6tables", "-A", c6, "-i", iface, "!", "-s", net6, "-j", "REJECT")
    add("ip6tables", "-A", c6, "-i", iface, "-o", iface, "-j", "REJECT")
    if mode == "routed":
        add("ip6tables", "-A", c6, "-i", iface, "-s", net6, "-o", wan6, "-j", "ACCEPT")
        add("ip6tables", "-A", c6, "-i", wan6, "-o", iface, "-d", net6, "-m", "conntrack", "--ctstate", "ESTABLISHED,RELATED", "-j", "ACCEPT")
        for kind in ("destination-unreachable", "packet-too-big", "time-exceeded", "parameter-problem"):
            add("ip6tables", "-A", c6, "-i", wan6, "-o", iface, "-d", net6,
                "-p", "ipv6-icmp", "--icmpv6-type", kind, "-j", "ACCEPT")
        add("ip6tables", "-A", c6, "-i", wan6, "-o", iface, "-d", net6, "-j", "REJECT")
    else:
        add("ip6tables", "-A", c6, "-i", iface, "-s", net6, "-j", "REJECT")
    add("ip6tables", "-A", i6, "-i", iface, "!", "-s", net6, "-j", "REJECT")
    add("ip6tables", "-A", i6, "-i", iface, "-s", net6, "-p", "tcp",
        "--dport", ssh_port, "-j", "ACCEPT")
    add("ip6tables", "-A", i6, "-i", iface, "-p", "ipv6-icmp", "-j", "ACCEPT")
    add("ip6tables", "-A", i6, "-i", iface, "-j", "REJECT")
    sysctls = [{"name": "net.ipv4.ip_forward", "applied": "1"}]
    if mode == "routed":
        sysctls.append({"name": "net.ipv6.conf.all.forwarding", "applied": "1"})
        # Keep router advertisements usable on the authoritative IPv6 WAN
        # after global forwarding changes the kernel's default RA behaviour.
        sysctls.append({"name": f"net.ipv6.conf.{wan6}.accept_ra", "applied": "2"})
    return rules, sysctls


def rule_present(argv):
    check = argv.copy()
    pos = check.index("-I") if "-I" in check else check.index("-A")
    check[pos] = "-C"
    if argv[pos] == "-I":
        del check[pos + 2]
    return run(check, check=False).returncode == 0


def apply(manifest):
    data = secure_json(manifest)
    wanted, sysctls = commands(data)
    previous = data["resources"].get("sysctls", [])
    originals = {entry.get("name"): entry.get("original") for entry in previous
                 if isinstance(entry, dict)}
    if previous:
        valid_owned(data)
    added = []
    changed = []
    try:
        for entry in sysctls:
            current = run(["sysctl", "-n", entry["name"]]).stdout.strip()
            entry["original"] = originals.get(entry["name"], current)
            if current != entry["applied"]:
                run(["sysctl", "-w", entry["name"] + "=" + entry["applied"]])
                changed.append(dict(entry, original=current))
        for argv in wanted:
            if argv[1] == "-N":
                if run([argv[0], "-L", argv[2]], check=False).returncode != 0:
                    run(argv); added.append(argv)
            elif not rule_present(argv):
                run(argv); added.append(argv)
        data["resources"] = {"rules": wanted, "routes": [], "sysctls": sysctls}
        atomic(manifest, data)
    except Exception:
        for argv in reversed(added):
            if argv[1] == "-N": run([argv[0], "-X", argv[2]], check=False)
            else:
                delete = argv.copy(); pos = delete.index("-I") if "-I" in delete else delete.index("-A"); delete[pos] = "-D"
                if argv[pos] == "-I": del delete[pos + 2]
                run(delete, check=False)
        for entry in reversed(changed):
            run(["sysctl", "-w", entry["name"] + "=" + entry["original"]], check=False)
        raise


def valid_owned(data):
    wanted, wanted_sysctls = commands(data)
    resources = data["resources"]
    if resources.get("routes") != [] or resources.get("rules") != wanted:
        raise FirewallError("invalid_resources")
    names = {x["name"] for x in wanted_sysctls}
    for entry in resources.get("sysctls", []):
        if (set(entry) != {"name", "original", "applied"}
                or entry["name"] not in names
                or entry["applied"] not in ("1", "2")
                or entry["original"] not in ("0", "1", "2")):
            raise FirewallError("invalid_resources")
    return wanted, resources["sysctls"]


def remove(manifest):
    data = secure_json(manifest)
    empty = {"rules": [], "routes": [], "sysctls": []}
    if data["resources"] == empty:
        return
    rules, sysctls = valid_owned(data)
    for argv in reversed(rules):
        if argv[1] == "-N": run([argv[0], "-F", argv[2]], check=False); run([argv[0], "-X", argv[2]], check=False)
        else:
            delete = argv.copy(); pos = delete.index("-I") if "-I" in delete else delete.index("-A"); delete[pos] = "-D"
            if argv[pos] == "-I": del delete[pos + 2]
            run(delete, check=False)
    for entry in sysctls:
        shared = False
        pattern = os.path.join(os.path.dirname(os.path.dirname(manifest)), "*", "manifest.json")
        for other_path in glob.glob(pattern):
            if os.path.realpath(other_path) == os.path.realpath(manifest):
                continue
            other = secure_json(other_path)
            if any(item.get("name") == entry["name"] and item.get("applied") == entry["applied"]
                   for item in other["resources"].get("sysctls", []) if isinstance(item, dict)):
                shared = True
                break
        if shared:
            continue
        current = run(["sysctl", "-n", entry["name"]]).stdout.strip()
        if current == entry["applied"]:
            run(["sysctl", "-w", entry["name"] + "=" + entry["original"]])
    data["resources"] = {"rules": [], "routes": [], "sysctls": []}
    atomic(manifest, data)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=("apply", "remove"))
    parser.add_argument("--manifest", required=True)
    args = parser.parse_args()
    (apply if args.action == "apply" else remove)(args.manifest)


if __name__ == "__main__":
    try: main()
    except (FirewallError, OSError, ValueError, KeyError, json.JSONDecodeError, subprocess.CalledProcessError) as error:
        print("ERR-NET-FIREWALL-UNSUPPORTED:" + str(error), file=os.sys.stderr)
        raise SystemExit(42)
