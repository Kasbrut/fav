#!/usr/bin/env python3
"""Fail-closed WireGuard profile renderer for FAV network schema v2."""

import argparse
import datetime
import ipaddress
import json
import os
import re
import stat
import sys
import tempfile


class RenderError(Exception):
    pass


def load_result(path):
    try:
        with open(path, encoding="utf-8") as source:
            value = json.load(source)
    except (OSError, ValueError) as error:
        raise RenderError("invalid_network_result") from error
    if not isinstance(value, dict) or value.get("schemaVersion") != 2:
        raise RenderError("unsupported_network_result")
    network = value.get("network")
    capability = value.get("capability")
    if not isinstance(network, dict) or not isinstance(capability, dict):
        raise RenderError("invalid_network_result")
    required = (
        "ipv4Subnet", "ipv6Mode", "ipv6Subnet", "fallbackIpv6Subnet",
        "serverIpv6Address", "wan4",
    )
    if any(not network.get(key) for key in required):
        raise RenderError("invalid_network_result")
    if value.get("installationId") != os.environ.get("FAV_INSTALLATION_ID"):
        raise RenderError("network_result_identity_mismatch")
    if value.get("operationId") != os.environ.get("FAV_OPERATION_ID"):
        raise RenderError("network_result_identity_mismatch")
    if type(value.get("revision")) is not int or value["revision"] != 1:
        raise RenderError("network_result_revision_mismatch")
    if network["ipv4Subnet"] != os.environ.get("VPN_SUBNET"):
        raise RenderError("network_result_ipv4_mismatch")
    try:
        ipv4 = ipaddress.ip_network(network["ipv4Subnet"], strict=True)
        ipv6 = ipaddress.ip_network(network["ipv6Subnet"], strict=True)
        fallback = ipaddress.ip_network(network["fallbackIpv6Subnet"], strict=True)
        server6 = ipaddress.ip_interface(network["serverIpv6Address"])
    except ValueError as error:
        raise RenderError("invalid_network_result") from error
    if ipv4.version != 4 or ipv4.prefixlen != 24:
        raise RenderError("invalid_network_result")
    if ipv6.version != 6 or ipv6.prefixlen != 64 or fallback.version != 6 or fallback.prefixlen != 64:
        raise RenderError("invalid_network_result")
    mode = network["ipv6Mode"]
    status = capability.get("status")
    reason = capability.get("reason")
    checked_at = capability.get("checkedAt")
    if status not in ("supported", "unavailable", "unknown") or not isinstance(reason, str) or not reason:
        raise RenderError("invalid_network_result")
    try:
        timestamp = datetime.datetime.fromisoformat(checked_at.replace("Z", "+00:00"))
    except (AttributeError, ValueError) as error:
        raise RenderError("invalid_network_result") from error
    if timestamp.tzinfo is None or timestamp.utcoffset() != datetime.timedelta(0):
        raise RenderError("invalid_network_result")
    try:
        requested_ula = ipaddress.ip_network(os.environ["VPN_IPV6_ULA_SUBNET"], strict=True)
    except (KeyError, ValueError) as error:
        raise RenderError("network_result_fallback_mismatch") from error
    if fallback != requested_ula or fallback.network_address.packed[0] != 0xFD:
        raise RenderError("network_result_fallback_mismatch")
    if mode not in ("routed", "blocked"):
        raise RenderError("invalid_network_result")
    if mode == "routed" and status != "supported":
        raise RenderError("network_result_capability_mismatch")
    if mode == "routed" and str(ipv6) != os.environ.get("VPN_IPV6_ROUTED_SUBNET"):
        raise RenderError("network_result_routed_mismatch")
    if mode == "blocked" and (status == "supported" or ipv6 != fallback):
        raise RenderError("network_result_capability_mismatch")
    if server6.network != ipv6 or server6.ip != ipv6.network_address + 1:
        raise RenderError("network_result_address_mismatch")
    return value, network, ipv4, ipv6


def settings(network):
    endpoint = os.environ.get("PUBLIC_ENDPOINT", "")
    dns_text = os.environ.get("DNS", "")
    port = os.environ.get("WG_PORT", "")
    ssh_port = os.environ.get("SSH_PORT", "")
    mtu = os.environ.get("MTU", "")
    if not endpoint or "\n" in endpoint or "\r" in endpoint:
        raise RenderError("invalid_endpoint")
    bracketed = endpoint.startswith("[") and endpoint.endswith("]")
    if bracketed:
        endpoint = endpoint[1:-1]
    try:
        endpoint_ip = ipaddress.ip_address(endpoint)
    except ValueError:
        endpoint_ip = None
        if bracketed:
            raise RenderError("invalid_endpoint")
        if not re.fullmatch(r"(?=.{1,253}\Z)(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)*[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?", endpoint):
            raise RenderError("invalid_endpoint")
    if not port.isdigit() or not 1 <= int(port) <= 65535:
        raise RenderError("invalid_port")
    if not ssh_port.isdigit() or not 1 <= int(ssh_port) <= 65535:
        raise RenderError("invalid_ssh_port")
    if not mtu.isdigit() or not 1280 <= int(mtu) <= 1500:
        raise RenderError("invalid_mtu")
    dns = [item.strip() for item in dns_text.split(",")]
    if not dns or any(not item for item in dns):
        raise RenderError("invalid_dns")
    try:
        resolvers = [ipaddress.ip_address(item) for item in dns]
    except ValueError as error:
        raise RenderError("invalid_dns") from error
    if any(item.is_unspecified or item.is_multicast for item in resolvers):
        raise RenderError("invalid_dns")
    if network["ipv6Mode"] == "blocked" and not any(item.version == 4 for item in resolvers):
        raise RenderError("blocked_mode_requires_ipv4_dns")
    shown_endpoint = f"[{endpoint}]" if endpoint_ip and endpoint_ip.version == 6 else endpoint
    return shown_endpoint, int(port), int(ssh_port), dns, int(mtu)


def key(directory, name):
    try:
        with open(os.path.join(directory, name), encoding="ascii") as source:
            value = source.read().strip()
    except OSError as error:
        raise RenderError("missing_key") from error
    if not re.fullmatch(r"[A-Za-z0-9+/]{43}=", value):
        raise RenderError("invalid_key")
    return value


def atomic_write(path, content, mode=0o600):
    directory = os.path.dirname(path)
    os.makedirs(directory, mode=0o700, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=".fav-profile.", dir=directory)
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


def render(args):
    result, network, ipv4, ipv6 = load_result(args.result)
    endpoint, port, ssh_port, dns, mtu = settings(network)
    server4 = ipv4.network_address + 1
    client4 = ipv4.network_address + 2
    server6 = ipv6.network_address + 1
    client6 = ipv6.network_address + 2
    iface = args.interface
    server_private = key(args.keys, f"{iface}_server_private.key")
    server_public = key(args.keys, f"{iface}_server_public.key")
    client_private = key(args.keys, f"{iface}_client_private.key")
    client_public = key(args.keys, f"{iface}_client_public.key")
    preshared = key(args.keys, f"{iface}_client_preshared.key")
    if args.kind == "manifest":
        content = None
    elif args.kind == "server":
        wan4 = network["wan4"]
        if not isinstance(wan4, str) or not re.fullmatch(r"[A-Za-z0-9_.:-]{1,15}", wan4):
            raise RenderError("invalid_wan4")
        content = f"""[Interface]
Address = {server4}/24, {server6}/64
ListenPort = {port}
MTU = {mtu}
PrivateKey = {server_private}
PostUp = python3 /etc/wireguard/fav/lib/firewall_manager.py apply --manifest /etc/wireguard/fav/{iface}/manifest.json
PostDown = python3 /etc/wireguard/fav/lib/firewall_manager.py remove --manifest /etc/wireguard/fav/{iface}/manifest.json

[Peer]
PublicKey = {client_public}
PresharedKey = {preshared}
AllowedIPs = {client4}/32, {client6}/128
"""
    else:
        content = f"""[Interface]
PrivateKey = {client_private}
Address = {client4}/32, {client6}/128
DNS = {', '.join(dns)}
MTU = {mtu}

[Peer]
PublicKey = {server_public}
PresharedKey = {preshared}
Endpoint = {endpoint}:{port}
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
"""
    if content is not None:
        atomic_write(args.output, content)
    if args.manifest or args.kind == "manifest":
        manifest_path = args.manifest or args.output
        manifest = dict(result)
        manifest.pop("operationId", None)
        manifest["state"] = "ready"
        manifest["interfaceName"] = iface
        manifest["network"] = dict(network, endpointHost=endpoint.strip("[]"), listenPort=port,
                                   managementSshPort=ssh_port, dns=dns, mtu=mtu)
        manifest["peers"] = [{"operationId": result["operationId"], "publicKey": client_public, "slot": 2, "ipv4Address": f"{client4}/32", "ipv6Address": f"{client6}/128", "profileVersion": 2}]
        resources = {"rules": [], "routes": [], "sysctls": []}
        if os.path.exists(manifest_path):
            info = os.lstat(manifest_path)
            required_uid = 0 if os.geteuid() == 0 else os.geteuid()
            if stat.S_ISLNK(info.st_mode) or info.st_uid != required_uid or stat.S_IMODE(info.st_mode) & 0o077:
                raise RenderError("unsafe_manifest")
            with open(manifest_path, encoding="utf-8") as existing_file:
                existing = json.load(existing_file)
            if existing.get("installationId") != result["installationId"] or existing.get("interfaceName") != iface:
                raise RenderError("manifest_identity")
            resources = existing.get("resources", resources)
        manifest["resources"] = resources
        manifest["pendingOperation"] = None
        atomic_write(manifest_path, json.dumps(manifest, separators=(",", ":"), sort_keys=True) + "\n")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("kind", choices=("server", "client", "manifest"))
    parser.add_argument("--result", required=True)
    parser.add_argument("--keys", required=True)
    parser.add_argument("--interface", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--manifest")
    args = parser.parse_args()
    render(args)


if __name__ == "__main__":
    try:
        main()
    except (RenderError, KeyError, TypeError) as error:
        print(f"ERR-NET-PROFILE-INVALID:{error}", file=sys.stderr)
        sys.exit(42)
