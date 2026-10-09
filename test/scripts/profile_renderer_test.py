import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest import mock


SCRIPT = Path(__file__).parents[2] / "lib/assets/scripts/lib/profile_renderer.py"
SPEC = importlib.util.spec_from_file_location("profile_renderer", SCRIPT)
renderer = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(renderer)


KEY = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="


class ProfileRendererTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.keys = self.root / "keys"
        self.keys.mkdir()
        for suffix in (
            "server_private", "server_public", "client_private",
            "client_public", "client_preshared",
        ):
            (self.keys / f"wg0_{suffix}.key").write_text(KEY + "\n")
        self.env = {
            "FAV_INSTALLATION_ID": "install-1",
            "FAV_OPERATION_ID": "operation-1",
            "VPN_SUBNET": "10.13.13.0/24",
            "VPN_IPV6_ULA_SUBNET": "fd12:3456:789a::/64",
            "VPN_IPV6_ROUTED_SUBNET": "2600:abcd:1234:5678::/64",
            "PUBLIC_ENDPOINT": "vpn.example.org",
            "WG_PORT": "51820",
            "SSH_PORT": "2222",
            "DNS": "1.1.1.1, 2606:4700:4700::1111",
            "MTU": "1420",
        }

    def tearDown(self):
        self.temp.cleanup()

    def result(self, mode="blocked"):
        prefix = "fd12:3456:789a::/64" if mode == "blocked" else "2600:abcd:1234:5678::/64"
        value = {
            "schemaVersion": 2,
            "installationId": "install-1",
            "operationId": "operation-1",
            "revision": 1,
            "network": {
                "ipv4Subnet": "10.13.13.0/24",
                "ipv6Mode": mode,
                "ipv6Subnet": prefix,
                "fallbackIpv6Subnet": "fd12:3456:789a::/64",
                "serverIpv6Address": prefix.replace("::/64", "::1/64"),
                "wan4": "eth0",
                "wan6": "eth1" if mode == "routed" else None,
            },
            "capability": {
                "status": "supported" if mode == "routed" else "unknown",
                "reason": "return_path_verified" if mode == "routed" else "probe_target_missing",
                "checkedAt": "2026-09-17T00:00:00Z",
            },
        }
        path = self.root / "network-result.json"
        path.write_text(json.dumps(value))
        return path

    def run_render(self, mode="blocked", endpoint=None):
        result = self.result(mode)
        output = self.root / f"{mode}.conf"
        manifest = self.root / "manifest.json"
        env = dict(self.env)
        if endpoint is not None:
            env["PUBLIC_ENDPOINT"] = endpoint
        args = type("Args", (), {
            "kind": "client", "result": str(result), "keys": str(self.keys),
            "interface": "wg0", "output": str(output), "manifest": str(manifest),
        })()
        with mock.patch.dict(os.environ, env, clear=True):
            renderer.render(args)
        return output.read_text(), json.loads(manifest.read_text())

    def test_routed_and_blocked_profiles_use_slot_two_and_both_defaults(self):
        for mode, address in (
            ("blocked", "fd12:3456:789a::2/128"),
            ("routed", "2600:abcd:1234:5678::2/128"),
        ):
            profile, manifest = self.run_render(mode)
            self.assertIn(f"Address = 10.13.13.2/32, {address}", profile)
            self.assertIn("AllowedIPs = 0.0.0.0/0, ::/0", profile)
            self.assertEqual(manifest["peers"][0]["slot"], 2)
            self.assertEqual(manifest["network"]["dns"], ["1.1.1.1", "2606:4700:4700::1111"])
            self.assertEqual(manifest["network"]["mtu"], 1420)
            self.assertEqual(manifest["network"]["managementSshPort"], 2222)

    def test_server_uses_slot_one_and_peer_host_routes_only(self):
        result = self.result("routed")
        output = self.root / "server.conf"
        args = type("Args", (), {
            "kind": "server", "result": str(result), "keys": str(self.keys),
            "interface": "wg0", "output": str(output), "manifest": None,
        })()
        with mock.patch.dict(os.environ, self.env, clear=True):
            renderer.render(args)
        profile = output.read_text()
        self.assertIn("Address = 10.13.13.1/24, 2600:abcd:1234:5678::1/64", profile)
        self.assertIn("AllowedIPs = 10.13.13.2/32, 2600:abcd:1234:5678::2/128", profile)
        self.assertNotIn("AllowedIPs = 0.0.0.0/0", profile)
        self.assertNotIn("NAT66", profile)

    def test_ipv4_dns_and_ipv6_endpoints_render_correctly(self):
        profile, _ = self.run_render(endpoint="203.0.113.10")
        self.assertIn("Endpoint = 203.0.113.10:51820", profile)
        profile, _ = self.run_render(endpoint="2001:db8::1")
        self.assertIn("Endpoint = [2001:db8::1]:51820", profile)

    def test_blocked_mode_rejects_ipv6_only_dns(self):
        env = dict(self.env, DNS="2606:4700:4700::1111")
        with mock.patch.dict(os.environ, env, clear=True):
            with self.assertRaisesRegex(renderer.RenderError, "blocked_mode_requires_ipv4_dns"):
                renderer.load_result(str(self.result("blocked")))[1]
                renderer.settings(renderer.load_result(str(self.result("blocked")))[1])

    def test_invalid_management_ssh_port_is_rejected(self):
        for value in ("", "0", "65536", "not-a-port"):
            env = dict(self.env, SSH_PORT=value)
            with mock.patch.dict(os.environ, env, clear=True):
                network = renderer.load_result(str(self.result("blocked")))[1]
                with self.assertRaisesRegex(renderer.RenderError, "invalid_ssh_port"):
                    renderer.settings(network)

    def test_mismatch_partial_corrupt_and_future_results_fail_closed(self):
        cases = []
        valid = json.loads(self.result().read_text())
        for mutate in (
            lambda value: value.update(schemaVersion=3),
            lambda value: value.pop("network"),
            lambda value: value["network"].update(ipv4Subnet="10.14.14.0/24"),
            lambda value: value["network"].update(serverIpv6Address="fd12:3456:789a::9/64"),
        ):
            value = json.loads(json.dumps(valid))
            mutate(value)
            cases.append(value)
        with mock.patch.dict(os.environ, self.env, clear=True):
            for index, value in enumerate(cases):
                path = self.root / f"bad-{index}.json"
                path.write_text(json.dumps(value))
                with self.assertRaises(renderer.RenderError):
                    renderer.load_result(str(path))
            corrupt = self.root / "corrupt.json"
            corrupt.write_text("{")
            with self.assertRaises(renderer.RenderError):
                renderer.load_result(str(corrupt))


if __name__ == "__main__":
    unittest.main()
