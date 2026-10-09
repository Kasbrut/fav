#!/usr/bin/env python3
"""Transactional, manifest-authoritative FAV v2 peer lifecycle."""

import argparse
import copy
import datetime
import ipaddress
import json
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import sys
import tempfile


class PeerError(Exception):
    pass


KEY_RE = re.compile(r"[A-Za-z0-9+/]{43}=")
TOKEN_RE = re.compile(r"[A-Za-z0-9][A-Za-z0-9._:-]{0,127}")
IFACE_RE = re.compile(r"[A-Za-z0-9_.-]{1,15}")


def fail(reason):
    raise PeerError(reason)


def atomic_write(path, content, mode=0o600):
    path = Path(path)
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=".fav-peer.", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as output:
            output.write(content)
            output.flush()
            os.fsync(output.fileno())
        os.chmod(temporary, mode)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def safe_file(path):
    path = Path(path)
    try:
        info = path.lstat()
    except OSError as error:
        fail("manifest_missing")
    required_uid = 0 if os.geteuid() == 0 else os.geteuid()
    if (stat.S_ISLNK(info.st_mode) or not stat.S_ISREG(info.st_mode)
            or info.st_uid != required_uid or stat.S_IMODE(info.st_mode) & 0o077):
        fail("unsafe_manifest")


def safe_directory(path):
    path = Path(path)
    try:
        info = path.lstat()
    except OSError as error:
        raise PeerError("unsafe_directory") from error
    required_uid = 0 if os.geteuid() == 0 else os.geteuid()
    if (stat.S_ISLNK(info.st_mode) or not stat.S_ISDIR(info.st_mode)
            or info.st_uid != required_uid or stat.S_IMODE(info.st_mode) & 0o077):
        fail("unsafe_directory")


def load_manifest(path, interface, installation):
    safe_directory(Path(path).parent)
    safe_file(path)
    try:
        value = json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, ValueError) as error:
        raise PeerError("invalid_manifest") from error
    if not isinstance(value, dict) or value.get("schemaVersion") != 2:
        fail("unsupported_manifest")
    if (value.get("state") not in ("ready", "updating") or value.get("interfaceName") != interface
            or value.get("installationId") != installation):
        fail("manifest_identity_or_state")
    if type(value.get("revision")) is not int or value["revision"] < 1:
        fail("invalid_manifest_revision")
    network = value.get("network")
    peers = value.get("peers")
    if not isinstance(network, dict) or not isinstance(peers, list):
        fail("partial_manifest")
    try:
        v4 = ipaddress.ip_network(network["ipv4Subnet"], strict=True)
        v6 = ipaddress.ip_network(network["ipv6Subnet"], strict=True)
        fallback = ipaddress.ip_network(network["fallbackIpv6Subnet"], strict=True)
        server6 = ipaddress.ip_interface(network["serverIpv6Address"])
    except (KeyError, ValueError, TypeError) as error:
        raise PeerError("invalid_manifest_network") from error
    if (v4.version != 4 or v4.prefixlen != 24 or v6.version != 6 or v6.prefixlen != 64
            or fallback.version != 6 or fallback.prefixlen != 64
            or fallback.network_address.packed[0] != 0xFD
            or server6.network != v6 or server6.ip != v6.network_address + 1):
        fail("invalid_manifest_network")
    if network.get("ipv6Mode") not in ("routed", "blocked"):
        fail("invalid_manifest_mode")
    capability = value.get("capability")
    if (not isinstance(capability, dict)
            or capability.get("status") not in ("supported", "unavailable", "unknown")
            or not isinstance(capability.get("reason"), str) or not capability["reason"]
            or not isinstance(capability.get("checkedAt"), str)):
        fail("invalid_manifest_capability")
    try:
        checked_at = datetime.datetime.fromisoformat(
            capability["checkedAt"].replace("Z", "+00:00"))
    except ValueError as error:
        raise PeerError("invalid_manifest_capability") from error
    if checked_at.tzinfo is None or checked_at.utcoffset() != datetime.timedelta(0):
        fail("invalid_manifest_capability")
    if network["ipv6Mode"] == "routed":
        if capability["status"] != "supported" or not isinstance(network.get("wan6"), str):
            fail("invalid_manifest_capability")
    elif capability["status"] == "supported" or v6 != fallback:
        fail("invalid_manifest_capability")
    for key in ("endpointHost", "listenPort", "dns", "mtu"):
        if key not in network:
            fail("partial_manifest_network")
    endpoint = network["endpointHost"]
    if not isinstance(endpoint, str) or not endpoint or "\n" in endpoint or "\r" in endpoint:
        fail("invalid_manifest_endpoint")
    try:
        ipaddress.ip_address(endpoint)
    except ValueError:
        if not re.fullmatch(r"(?=.{1,253}\Z)(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)*[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?", endpoint):
            fail("invalid_manifest_endpoint")
    if type(network["listenPort"]) is not int or not 1 <= network["listenPort"] <= 65535:
        fail("invalid_manifest_port")
    if type(network["mtu"]) is not int or not 1280 <= network["mtu"] <= 1500:
        fail("invalid_manifest_mtu")
    if not isinstance(network["dns"], list) or not network["dns"]:
        fail("invalid_manifest_dns")
    try:
        resolvers = [ipaddress.ip_address(item) for item in network["dns"]]
    except (ValueError, TypeError) as error:
        raise PeerError("invalid_manifest_dns") from error
    if any(item.is_unspecified or item.is_multicast for item in resolvers):
        fail("invalid_manifest_dns")
    if network["ipv6Mode"] == "blocked" and not any(item.version == 4 for item in resolvers):
        fail("invalid_manifest_dns")
    resources = value.get("resources")
    if not isinstance(resources, dict) or resources.get("routes") != []:
        fail("invalid_manifest_resources")
    rules = resources.get("rules")
    sysctls = resources.get("sysctls")
    if (not isinstance(rules, list) or not isinstance(sysctls, list)
            or any(not isinstance(argv, list) or not argv
                   or argv[0] not in ("iptables", "ip6tables")
                   or any(not isinstance(item, str) for item in argv) for argv in rules)
            or any(not isinstance(item, dict)
                   or set(item) != {"name", "original", "applied"}
                   or not all(isinstance(item[key], str) for key in item) for item in sysctls)):
        fail("invalid_manifest_resources")
    validate_peers(peers, v4, v6)
    pending = value.get("pendingOperation")
    if value["state"] == "ready" and pending is not None:
        fail("invalid_pending_operation")
    if value["state"] == "updating" and (not isinstance(pending, dict)
            or set(pending) != {"type", "operationId", "publicKey", "slot"}
            or pending["type"] not in ("add", "revoke")
            or not TOKEN_RE.fullmatch(pending["operationId"])
            or not KEY_RE.fullmatch(pending["publicKey"])
            or type(pending["slot"]) is not int):
        fail("invalid_pending_operation")
    return value, v4, v6


def validate_peers(peers, v4, v6):
    slots, keys, operations = {1}, set(), set()
    for peer in peers:
        if not isinstance(peer, dict) or set(("operationId", "publicKey", "slot", "ipv4Address", "ipv6Address", "profileVersion")) - set(peer):
            fail("invalid_manifest_peer")
        slot = peer["slot"]
        if type(slot) is not int or not 2 <= slot <= 254 or slot in slots:
            fail("invalid_manifest_peer")
        if not KEY_RE.fullmatch(peer["publicKey"]) or peer["publicKey"] in keys:
            fail("invalid_manifest_peer")
        if not TOKEN_RE.fullmatch(peer["operationId"]) or peer["operationId"] in operations:
            fail("invalid_manifest_peer")
        if peer["profileVersion"] != 2 or peer["ipv4Address"] != f"{v4.network_address + slot}/32" or peer["ipv6Address"] != f"{v6.network_address + slot}/128":
            fail("invalid_manifest_peer")
        slots.add(slot); keys.add(peer["publicKey"]); operations.add(peer["operationId"])


def run_wg(*args, input_text=None, check=True):
    result = subprocess.run(["wg", *args], input=input_text, text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if check and result.returncode:
        fail("wg_failed")
    return result


def conf_peers(path):
    try:
        text = Path(path).read_text(encoding="utf-8")
    except OSError as error:
        raise PeerError("config_missing") from error
    found, block = {}, None
    for raw in text.splitlines():
        line = raw.strip()
        if line == "[Peer]": block = {}
        elif line.startswith("["): block = None
        elif block is not None and "=" in line:
            key, value = (part.strip() for part in line.split("=", 1))
            block[key] = value
            if key == "AllowedIPs" and KEY_RE.fullmatch(block.get("PublicKey", "")):
                found[block["PublicKey"]] = set(x.strip() for x in value.split(","))
    return found


def runtime_peers(interface):
    result = run_wg("show", interface, "allowed-ips")
    found = {}
    for line in result.stdout.splitlines():
        fields = line.split("\t")
        if len(fields) == 2 and KEY_RE.fullmatch(fields[0]):
            found[fields[0]] = set(
                x for x in re.split(r"[\s,]+", fields[1].strip()) if x
            )
    return found


def ensure_parity(manifest, configured, runtime):
    expected = {p["publicKey"]: {p["ipv4Address"], p["ipv6Address"]} for p in manifest["peers"]}
    for key, addresses in expected.items():
        if configured.get(key) != addresses or runtime.get(key) != addresses:
            fail("peer_state_drift")
    extras = (set(configured) | set(runtime)) - set(expected)
    if extras:
        fail("unmanaged_peer_drift")


def backup(root, manifest_path, conf_path):
    backup_dir = root / ".peer-backup"
    if backup_dir.exists() and backup_dir.is_symlink(): fail("unsafe_backup")
    backup_dir.mkdir(mode=0o700, exist_ok=True)
    os.chmod(backup_dir, 0o700)
    shutil.copyfile(manifest_path, backup_dir / "manifest.json")
    shutil.copyfile(conf_path, backup_dir / "interface.conf")
    os.chmod(backup_dir / "manifest.json", 0o600)
    os.chmod(backup_dir / "interface.conf", 0o600)
    return backup_dir


def restore(backup_dir, manifest_path, conf_path):
    if backup_dir.exists():
        atomic_write(manifest_path, (backup_dir / "manifest.json").read_text(encoding="utf-8"))
        atomic_write(conf_path, (backup_dir / "interface.conf").read_text(encoding="utf-8"))


def owned_secret_paths(root, wg_dir, interface, peer):
    directory = secret_dir(root, peer["operationId"])
    if directory.exists():
        return [directory]
    if peer["slot"] == 2:
        base = Path(wg_dir)
        return [base / f"{interface}_client_{name}.key"
                for name in ("private", "public", "preshared")]
    return []


def stash_secrets(paths, backup_dir):
    stash = backup_dir / "secrets"
    stash.mkdir(mode=0o700)
    moved = []
    for index, source in enumerate(paths):
        if not source.exists():
            continue
        target = stash / f"{index}-{source.name}"
        os.replace(source, target)
        moved.append((source, target))
    return moved


def restore_secrets(moved):
    for destination, source in moved:
        destination.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        os.replace(source, destination)


def recover_pending(manifest, root, manifest_path, conf_path, interface):
    pending = manifest.get("pendingOperation")
    if pending is None:
        return
    backup_dir = root / ".peer-backup"
    if not backup_dir.exists() or backup_dir.is_symlink() or stat.S_IMODE(backup_dir.stat().st_mode) & 0o077:
        fail("unsafe_backup")
    safe_file(backup_dir / "manifest.json")
    safe_file(backup_dir / "interface.conf")
    restore(backup_dir, manifest_path, conf_path)
    if pending["type"] == "add":
        run_wg("set", interface, "peer", pending["publicKey"], "remove", check=False)
        shutil.rmtree(secret_dir(root, pending["operationId"]), ignore_errors=True)
    else:
        restored = json.loads((backup_dir / "manifest.json").read_text(encoding="utf-8"))
        peer = next((p for p in restored["peers"] if p["publicKey"] == pending["publicKey"]), None)
        if peer is None: fail("invalid_pending_operation")
        paths = owned_secret_paths(root, root.parent.parent, interface, peer)
        moved = []
        stash = backup_dir / "secrets"
        if stash.exists():
            stored = sorted(stash.iterdir())
            for item in stored:
                original = (secret_dir(root, peer["operationId"]) if item.is_dir()
                            else Path(root.parent.parent) / item.name.split("-", 1)[1])
                moved.append((original, item))
        psk = next((target / "preshared.key" if target.is_dir() else target
                    for original, target in moved
                    if target.is_dir() or "preshared" in original.name), None)
        if psk is None:
            psk = next((path / "preshared.key" if path.is_dir() else path
                        for path in paths if path.is_dir() or "preshared" in path.name), None)
        if psk is None: fail("missing_key")
        run_wg("set", interface, "peer", peer["publicKey"], "preshared-key",
               str(psk),
               "allowed-ips", f"{peer['ipv4Address']},{peer['ipv6Address']}")
        restore_secrets(moved)
    shutil.rmtree(backup_dir)


def remove_committed_backup(root):
    backup_dir = root / ".peer-backup"
    if not backup_dir.exists():
        return
    safe_directory(backup_dir)
    shutil.rmtree(backup_dir)


def save_manifest(path, manifest):
    atomic_write(path, json.dumps(manifest, separators=(",", ":"), sort_keys=True) + "\n")


def secret_dir(root, operation):
    if not TOKEN_RE.fullmatch(operation): fail("invalid_operation_id")
    return root / "peers" / operation


def read_key(path):
    safe_file(path)
    value = Path(path).read_text(encoding="ascii").strip()
    if not KEY_RE.fullmatch(value): fail("invalid_key")
    return value


def render_envelope(manifest, peer, secrets, server_key):
    network = manifest["network"]
    endpoint = network["endpointHost"]
    try:
        if ipaddress.ip_address(endpoint).version == 6: endpoint = f"[{endpoint}]"
    except ValueError:
        pass
    private = read_key(secrets / "private.key")
    psk = read_key(secrets / "preshared.key")
    dns = network["dns"]
    if not isinstance(dns, list) or not dns: fail("invalid_manifest_dns")
    profile = f"""[Interface]
PrivateKey = {private}
Address = {peer['ipv4Address']}, {peer['ipv6Address']}
DNS = {', '.join(dns)}
MTU = {network['mtu']}

[Peer]
PublicKey = {server_key}
PresharedKey = {psk}
Endpoint = {endpoint}:{network['listenPort']}
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
"""
    print("FAV_ENVELOPE_VERSION=2")
    print(f"INSTALLATION_ID={manifest['installationId']}")
    print(f"OPERATION_ID={peer['operationId']}")
    print(f"REVISION={manifest['revision']}")
    print(f"IPV6_MODE={network['ipv6Mode']}")
    print(f"ADDR4={peer['ipv4Address']}")
    print(f"ADDR6={peer['ipv6Address']}")
    print(f"PUBKEY={peer['publicKey']}")
    print("---BEGIN-CONF---")
    print(profile, end="")
    print("---END-CONF---")


def add(args, manifest, v4, v6, root, manifest_path, conf_path):
    existing = next((p for p in manifest["peers"] if p["operationId"] == args.operation), None)
    secrets = secret_dir(root, args.operation)
    if existing:
        safe_directory(secrets)
        configured, runtime = conf_peers(conf_path), runtime_peers(args.interface)
        ensure_parity(manifest, configured, runtime)
        render_envelope(manifest, existing, secrets, read_key(Path(args.wg_dir) / f"{args.interface}_server_public.key"))
        return
    if manifest.get("pendingOperation") is not None: fail("pending_operation_conflict")
    configured, runtime = conf_peers(conf_path), runtime_peers(args.interface)
    ensure_parity(manifest, configured, runtime)
    used = {1}
    for addresses in list(configured.values()) + list(runtime.values()):
        for address in addresses:
            try:
                ip = ipaddress.ip_interface(address).ip
            except ValueError: continue
            if ip in v4 or ip in v6: used.add(int(ip) - int(v4.network_address if ip.version == 4 else v6.network_address))
    used.update(p["slot"] for p in manifest["peers"])
    slot = next((n for n in range(2, 255) if n not in used), None)
    if slot is None: fail("pool_exhausted")
    peers_root = root / "peers"
    if peers_root.exists():
        safe_directory(peers_root)
    else:
        peers_root.mkdir(mode=0o700)
    secrets.mkdir(mode=0o700, exist_ok=False)
    private = run_wg("genkey").stdout.strip()
    public = run_wg("pubkey", input_text=private + "\n").stdout.strip()
    psk = run_wg("genpsk").stdout.strip()
    if not all(KEY_RE.fullmatch(x) for x in (private, public, psk)): fail("invalid_generated_key")
    for name, value in (("private.key", private), ("public.key", public), ("preshared.key", psk)):
        atomic_write(secrets / name, value + "\n")
    peer = {"operationId": args.operation, "publicKey": public, "slot": slot,
            "ipv4Address": f"{v4.network_address + slot}/32",
            "ipv6Address": f"{v6.network_address + slot}/128", "profileVersion": 2}
    backup_dir = backup(root, manifest_path, conf_path)
    pending = copy.deepcopy(manifest); pending["state"] = "updating"
    pending["pendingOperation"] = {"type": "add", "operationId": args.operation,
                                     "publicKey": public, "slot": slot}
    save_manifest(manifest_path, pending)
    try:
        original = Path(conf_path).read_text(encoding="utf-8")
        label = re.sub(r"[^A-Za-z0-9 ._-]", "", args.label)[:32]
        block = f"\n# label: {label}\n[Peer]\nPublicKey = {public}\nPresharedKey = {psk}\nAllowedIPs = {peer['ipv4Address']}, {peer['ipv6Address']}\n"
        atomic_write(conf_path, original + block)
        run_wg("set", args.interface, "peer", public, "preshared-key", str(secrets / "preshared.key"),
               "allowed-ips", f"{peer['ipv4Address']},{peer['ipv6Address']}")
        if runtime_peers(args.interface).get(public) != {peer["ipv4Address"], peer["ipv6Address"]}: fail("runtime_verify_failed")
        manifest["peers"].append(peer); manifest["revision"] += 1
        manifest["pendingOperation"] = None; manifest["state"] = "ready"
        save_manifest(manifest_path, manifest)
        shutil.rmtree(backup_dir)
    except BaseException:
        run_wg("set", args.interface, "peer", public, "remove", check=False)
        restore(backup_dir, manifest_path, conf_path)
        shutil.rmtree(secrets, ignore_errors=True)
        shutil.rmtree(backup_dir, ignore_errors=True)
        raise
    render_envelope(manifest, peer, secrets, read_key(Path(args.wg_dir) / f"{args.interface}_server_public.key"))


def remove_block(text, public):
    chunks = re.split(r"(?=^\[Peer\]\s*$)", text, flags=re.MULTILINE)
    kept, removed = [], False
    for chunk in chunks:
        if chunk.startswith("[Peer]") and re.search(rf"^PublicKey\s*=\s*{re.escape(public)}\s*$", chunk, re.MULTILINE):
            if kept: kept[-1] = re.sub(r"\n?# label: [^\n]*\n?$", "\n", kept[-1])
            removed = True
        else: kept.append(chunk)
    if not removed: fail("config_peer_missing")
    return "".join(kept)


def revoke(args, manifest, _v4, _v6, root, manifest_path, conf_path):
    last = manifest.get("lastOperation")
    if isinstance(last, dict) and last == {"type": "revoke", "operationId": args.operation, "publicKey": args.public_key}:
        print(f"FAV-REVOKED REVISION={manifest['revision']}")
        return
    if manifest.get("pendingOperation") is not None: fail("pending_operation_conflict")
    peer = next((p for p in manifest["peers"] if p["publicKey"] == args.public_key), None)
    if peer is None: fail("peer_not_found")
    configured, runtime = conf_peers(conf_path), runtime_peers(args.interface)
    ensure_parity(manifest, configured, runtime)
    backup_dir = backup(root, manifest_path, conf_path)
    pending = copy.deepcopy(manifest); pending["state"] = "updating"
    pending["pendingOperation"] = {"type": "revoke", "operationId": args.operation,
                                     "publicKey": args.public_key, "slot": peer["slot"]}
    save_manifest(manifest_path, pending)
    moved_secrets = []
    try:
        atomic_write(conf_path, remove_block(Path(conf_path).read_text(encoding="utf-8"), args.public_key))
        run_wg("set", args.interface, "peer", args.public_key, "remove")
        if args.public_key in runtime_peers(args.interface): fail("runtime_verify_failed")
        moved_secrets = stash_secrets(
            owned_secret_paths(root, args.wg_dir, args.interface, peer), backup_dir)
        manifest["peers"] = [p for p in manifest["peers"] if p["publicKey"] != args.public_key]
        manifest["revision"] += 1; manifest["pendingOperation"] = None; manifest["state"] = "ready"
        manifest["lastOperation"] = {"type": "revoke", "operationId": args.operation, "publicKey": args.public_key}
        save_manifest(manifest_path, manifest)
        shutil.rmtree(backup_dir)
    except BaseException:
        restore(backup_dir, manifest_path, conf_path)
        psk = next((target / "preshared.key" if target.is_dir() else target
                    for original, target in moved_secrets
                    if target.is_dir() or "preshared" in original.name), None)
        if psk is None:
            paths = owned_secret_paths(root, args.wg_dir, args.interface, peer)
            psk = next((path / "preshared.key" if path.is_dir() else path
                        for path in paths if path.is_dir() or "preshared" in path.name), None)
        run_wg("set", args.interface, "peer", args.public_key, "preshared-key",
               str(psk),
               "allowed-ips", f"{peer['ipv4Address']},{peer['ipv6Address']}", check=False)
        restore_secrets(moved_secrets)
        shutil.rmtree(backup_dir, ignore_errors=True)
        raise
    print(f"FAV-REVOKED REVISION={manifest['revision']}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=("add", "revoke"))
    parser.add_argument("--interface", required=True)
    parser.add_argument("--installation", required=True)
    parser.add_argument("--operation", required=True)
    parser.add_argument("--label", default="")
    parser.add_argument("--public-key", default="")
    parser.add_argument("--wg-dir", default=os.environ.get("WG_DIR", "/etc/wireguard"))
    args = parser.parse_args()
    if not IFACE_RE.fullmatch(args.interface) or not TOKEN_RE.fullmatch(args.installation) or not TOKEN_RE.fullmatch(args.operation): fail("invalid_identity")
    if args.action == "revoke" and not KEY_RE.fullmatch(args.public_key): fail("invalid_public_key")
    wg_dir = Path(args.wg_dir)
    root = wg_dir / "fav" / args.interface
    manifest_path, conf_path = root / "manifest.json", wg_dir / f"{args.interface}.conf"
    safe_file(conf_path)
    manifest, v4, v6 = load_manifest(manifest_path, args.interface, args.installation)
    if manifest.get("pendingOperation") is not None:
        recover_pending(manifest, root, manifest_path, conf_path, args.interface)
        manifest, v4, v6 = load_manifest(manifest_path, args.interface, args.installation)
    else:
        remove_committed_backup(root)
    if args.action == "add": add(args, manifest, v4, v6, root, manifest_path, conf_path)
    else: revoke(args, manifest, v4, v6, root, manifest_path, conf_path)


if __name__ == "__main__":
    try:
        main()
    except (PeerError, OSError, ValueError, TypeError, KeyError) as error:
        reason = str(error)
        token = "ERR-PEER-SUBNET-EXHAUSTED" if reason == "pool_exhausted" else "ERR-PEER-NOT-FOUND" if reason == "peer_not_found" else "ERR-PEER-APPLY-FAILED"
        print(token, file=sys.stderr)
        sys.exit(41 if reason == "pool_exhausted" else 42 if reason == "peer_not_found" else 40)
