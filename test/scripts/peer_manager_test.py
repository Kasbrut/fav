import importlib.util
import base64
import json
import os
from pathlib import Path
import stat
import tempfile
import types
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[2]
PATH = ROOT / "lib/assets/scripts/lib/peer_manager.py"
SPEC = importlib.util.spec_from_file_location("peer_manager", PATH)
pm = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(pm)

K1 = "A" * 43 + "="
K2 = "B" * 43 + "="
PRIV = "C" * 43 + "="
PSK = "D" * 43 + "="
SERVER = "E" * 43 + "="


class PeerManagerTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.wg = Path(self.tmp.name) / "etc/wireguard"
        self.root = self.wg / "fav/wg0"
        self.root.mkdir(parents=True)
        os.chmod(self.root, 0o700)
        self.manifest_path = self.root / "manifest.json"
        self.conf_path = self.wg / "wg0.conf"
        self.runtime = {K1: {"10.13.13.2/32", "fd12:3456:789a::2/128"}}
        self.manifest = {
            "schemaVersion": 2, "installationId": "install-1", "revision": 1,
            "state": "ready", "interfaceName": "wg0",
            "network": {"ipv4Subnet": "10.13.13.0/24", "ipv6Mode": "blocked",
                        "ipv6Subnet": "fd12:3456:789a::/64",
                        "fallbackIpv6Subnet": "fd12:3456:789a::/64",
                        "serverIpv6Address": "fd12:3456:789a::1/64",
                        "endpointHost": "vpn.example.org", "listenPort": 51820,
                        "dns": ["1.1.1.1"], "mtu": 1420, "wan4": "eth0", "wan6": None},
            "capability": {"status": "unknown", "reason": "test", "checkedAt": "2026-09-17T00:00:00Z"},
            "peers": [{"operationId": "first-op", "publicKey": K1, "slot": 2,
                       "ipv4Address": "10.13.13.2/32", "ipv6Address": "fd12:3456:789a::2/128", "profileVersion": 2}],
            "resources": {"rules": [], "routes": [], "sysctls": []}, "pendingOperation": None,
        }
        self._write_state()
        pm.atomic_write(self.wg / "wg0_server_public.key", SERVER + "\n")
        first = self.root / "peers/first-op"; first.mkdir(parents=True)
        os.chmod(first.parent, 0o700); os.chmod(first, 0o700)
        pm.atomic_write(first / "preshared.key", PSK + "\n")

    def tearDown(self): self.tmp.cleanup()

    def _write_state(self):
        pm.atomic_write(self.manifest_path, json.dumps(self.manifest) + "\n")
        peers = ""
        for peer in self.manifest["peers"]:
            peers += f"\n# label: peer\n[Peer]\nPublicKey = {peer['publicKey']}\nPresharedKey = {PSK}\nAllowedIPs = {peer['ipv4Address']}, {peer['ipv6Address']}\n"
        pm.atomic_write(self.conf_path, "[Interface]\nPrivateKey = hidden\n" + peers)

    def _wg(self, *args, input_text=None, check=True):
        if args[:3] == ("show", "wg0", "allowed-ips"):
            text = "".join(f"{key}\t{','.join(sorted(value))}\n" for key, value in self.runtime.items())
            return types.SimpleNamespace(stdout=text, returncode=0)
        if args == ("genkey",): return types.SimpleNamespace(stdout=PRIV + "\n", returncode=0)
        if args == ("pubkey",): return types.SimpleNamespace(stdout=K2 + "\n", returncode=0)
        if args == ("genpsk",): return types.SimpleNamespace(stdout=PSK + "\n", returncode=0)
        if args[:3] == ("set", "wg0", "peer"):
            key = args[3]
            if args[4] == "remove": self.runtime.pop(key, None)
            else: self.runtime[key] = set(args[-1].split(","))
            return types.SimpleNamespace(stdout="", returncode=0)
        raise AssertionError(args)

    def _args(self, action="add", operation="add-op", public_key=""):
        return types.SimpleNamespace(action=action, interface="wg0", installation="install-1",
                                     operation=operation, label="phone", public_key=public_key,
                                     wg_dir=str(self.wg))

    def test_runtime_peers_accepts_real_wg_space_separated_allowed_ips(self):
        output = f"{K1}\t10.13.13.2/32 fd12:3456:789a::2/128\n"
        result = types.SimpleNamespace(stdout=output, returncode=0)
        with mock.patch.object(pm, "run_wg", return_value=result):
            self.assertEqual(pm.runtime_peers("wg0"), self.runtime)

    def test_add_allocates_same_free_slot_and_is_idempotent_after_lost_response(self):
        with mock.patch.object(pm, "run_wg", self._wg):
            manifest, v4, v6 = pm.load_manifest(self.manifest_path, "wg0", "install-1")
            pm.add(self._args(), manifest, v4, v6, self.root, self.manifest_path, self.conf_path)
            committed = json.loads(self.manifest_path.read_text())
            self.assertEqual((committed["peers"][-1]["ipv4Address"], committed["peers"][-1]["ipv6Address"]),
                             ("10.13.13.3/32", "fd12:3456:789a::3/128"))
            self.assertEqual(committed["revision"], 2)
            pm.add(self._args(), committed, v4, v6, self.root, self.manifest_path, self.conf_path)
            self.assertEqual(len(json.loads(self.manifest_path.read_text())["peers"]), 2)

    def test_routed_add_uses_authoritative_global_prefix(self):
        self.manifest["network"].update(
            ipv6Mode="routed", ipv6Subnet="2600:abcd:1234:5678::/64",
            serverIpv6Address="2600:abcd:1234:5678::1/64", wan6="eth1")
        self.manifest["capability"]["status"] = "supported"
        self.manifest["peers"][0]["ipv6Address"] = "2600:abcd:1234:5678::2/128"
        self.runtime[K1] = {"10.13.13.2/32", "2600:abcd:1234:5678::2/128"}
        self._write_state()
        with mock.patch.object(pm, "run_wg", self._wg):
            manifest, v4, v6 = pm.load_manifest(self.manifest_path, "wg0", "install-1")
            pm.add(self._args(), manifest, v4, v6, self.root, self.manifest_path, self.conf_path)
        self.assertEqual(json.loads(self.manifest_path.read_text())["peers"][-1]["ipv6Address"],
                         "2600:abcd:1234:5678::3/128")

    def test_collision_in_runtime_is_not_allocated_and_slot_one_is_reserved(self):
        self.runtime[K2] = {"10.13.13.3/32", "fd12:3456:789a::3/128"}
        with mock.patch.object(pm, "run_wg", self._wg):
            manifest, v4, v6 = pm.load_manifest(self.manifest_path, "wg0", "install-1")
            with self.assertRaisesRegex(pm.PeerError, "unmanaged_peer_drift"):
                pm.add(self._args(), manifest, v4, v6, self.root, self.manifest_path, self.conf_path)
        used = {1, *range(2, 255)}
        self.assertIsNone(next((n for n in range(2, 255) if n not in used), None))

    def test_full_pool_fails_without_generating_secrets(self):
        peers = []
        self.runtime = {}
        for slot in range(2, 255):
            key = base64.b64encode(slot.to_bytes(32, "big")).decode()
            peer = {"operationId": f"op-{slot}", "publicKey": key, "slot": slot,
                    "ipv4Address": f"10.13.13.{slot}/32",
                    "ipv6Address": f"fd12:3456:789a::{slot:x}/128", "profileVersion": 2}
            peers.append(peer); self.runtime[key] = {peer["ipv4Address"], peer["ipv6Address"]}
        self.manifest["peers"] = peers; self._write_state()
        with mock.patch.object(pm, "run_wg", self._wg):
            manifest, v4, v6 = pm.load_manifest(self.manifest_path, "wg0", "install-1")
            with self.assertRaisesRegex(pm.PeerError, "pool_exhausted"):
                pm.add(self._args(), manifest, v4, v6, self.root, self.manifest_path, self.conf_path)
        self.assertFalse((self.root / "peers/add-op").exists())

    def test_revoke_removes_config_runtime_manifest_and_secret_then_is_idempotent(self):
        with mock.patch.object(pm, "run_wg", self._wg):
            manifest, v4, v6 = pm.load_manifest(self.manifest_path, "wg0", "install-1")
            pm.revoke(self._args("revoke", "revoke-op", K1), manifest, v4, v6,
                      self.root, self.manifest_path, self.conf_path)
            committed = json.loads(self.manifest_path.read_text())
            self.assertEqual(committed["peers"], [])
            self.assertNotIn(K1, self.runtime)
            self.assertNotIn(K1, self.conf_path.read_text())
            self.assertFalse((self.root / "peers/first-op").exists())
            pm.revoke(self._args("revoke", "revoke-op", K1), committed, v4, v6,
                      self.root, self.manifest_path, self.conf_path)

    def test_add_failure_rolls_back_only_current_operation(self):
        original_manifest = self.manifest_path.read_text()
        original_conf = self.conf_path.read_text()
        def failing_wg(*args, input_text=None, check=True):
            if args[:4] == ("set", "wg0", "peer", K2) and args[4] != "remove":
                raise pm.PeerError("injected_apply_failure")
            return self._wg(*args, input_text=input_text, check=check)
        with mock.patch.object(pm, "run_wg", failing_wg):
            manifest, v4, v6 = pm.load_manifest(self.manifest_path, "wg0", "install-1")
            with self.assertRaisesRegex(pm.PeerError, "injected_apply_failure"):
                pm.add(self._args(), manifest, v4, v6, self.root, self.manifest_path, self.conf_path)
        self.assertEqual(self.manifest_path.read_text(), original_manifest)
        self.assertEqual(self.conf_path.read_text(), original_conf)
        self.assertIn(K1, self.runtime)
        self.assertFalse((self.root / "peers/add-op").exists())

    def test_reconciles_interrupted_pending_add_from_protected_backup(self):
        backup = pm.backup(self.root, self.manifest_path, self.conf_path)
        pending = json.loads(self.manifest_path.read_text())
        pending["state"] = "updating"
        pending["pendingOperation"] = {"type": "add", "operationId": "add-op",
                                       "publicKey": K2, "slot": 3}
        pm.save_manifest(self.manifest_path, pending)
        self.runtime[K2] = {"10.13.13.3/32", "fd12:3456:789a::3/128"}
        (self.root / "peers/add-op").mkdir(parents=True)
        with mock.patch.object(pm, "run_wg", self._wg):
            loaded, _, _ = pm.load_manifest(self.manifest_path, "wg0", "install-1")
            pm.recover_pending(loaded, self.root, self.manifest_path, self.conf_path, "wg0")
        self.assertEqual(json.loads(self.manifest_path.read_text())["state"], "ready")
        self.assertNotIn(K2, self.runtime)
        self.assertFalse(backup.exists())

    def test_rejects_future_symlink_insecure_and_incoherent_manifests(self):
        for mutate in (
            lambda m: m.update(schemaVersion=3),
            lambda m: m.update(state="updating"),
            lambda m: m["peers"][0].update(ipv6Address="fd12:3456:789a::9/128"),
        ):
            value = json.loads(json.dumps(self.manifest)); mutate(value)
            pm.atomic_write(self.manifest_path, json.dumps(value))
            with self.assertRaises(pm.PeerError):
                pm.load_manifest(self.manifest_path, "wg0", "install-1")
        self._write_state(); os.chmod(self.manifest_path, 0o644)
        with self.assertRaisesRegex(pm.PeerError, "unsafe_manifest"):
            pm.load_manifest(self.manifest_path, "wg0", "install-1")
        self.manifest_path.unlink(); self.manifest_path.symlink_to(self.conf_path)
        with self.assertRaisesRegex(pm.PeerError, "unsafe_manifest"):
            pm.load_manifest(self.manifest_path, "wg0", "install-1")

    def test_manifest_and_errors_never_contain_server_secrets_or_argv(self):
        text = self.manifest_path.read_text()
        self.assertNotIn(PRIV, text); self.assertNotIn(PSK, text)
        self.manifest["resources"]["rules"] = [["sh", "-c", "owned"]]
        self._write_state()
        with self.assertRaisesRegex(pm.PeerError, "invalid_manifest_resources"):
            pm.load_manifest(self.manifest_path, "wg0", "install-1")


if __name__ == "__main__": unittest.main()
