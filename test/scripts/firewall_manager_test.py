import importlib.util
import json
import os
import stat
import tempfile
import types
import unittest
from pathlib import Path
from unittest import mock

SCRIPT = Path(__file__).parents[2] / "lib/assets/scripts/lib/firewall_manager.py"
SPEC = importlib.util.spec_from_file_location("firewall_manager", SCRIPT)
fw = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(fw)


def manifest(mode="routed", wan4="eth4", wan6="eth6"):
    return {
        "schemaVersion": 2, "installationId": "install-1", "revision": 1,
        "state": "ready", "interfaceName": "wg0", "peers": [],
        "network": {"ipv4Subnet": "10.13.13.0/24", "ipv6Mode": mode,
                    "ipv6Subnet": "2600:abcd:1234:5678::/64" if mode == "routed" else "fd12:3456:789a::/64",
                    "wan4": wan4, "wan6": wan6 if mode == "routed" else None,
                    "managementSshPort": 2222},
        "resources": {"rules": [], "routes": [], "sysctls": []},
    }


class FirewallManagerTest(unittest.TestCase):
    def test_routed_uses_distinct_wans_pmtu_and_never_nat66(self):
        rules, sysctls = fw.commands(manifest())
        joined = [" ".join(rule) for rule in rules]
        self.assertTrue(any("iptables -t nat" in rule and "-o eth4" in rule for rule in joined))
        self.assertTrue(any("ip6tables" in rule and "-o eth6" in rule for rule in joined))
        self.assertTrue(any("packet-too-big" in rule for rule in joined))
        self.assertTrue(any("ESTABLISHED,RELATED" in rule for rule in joined))
        self.assertFalse(any("ip6tables -t nat" in rule or "MASQUERADE" in rule and rule.startswith("ip6tables") for rule in joined))
        self.assertFalse(any("proxy_ndp" in rule or "nat64" in rule.lower() for rule in joined))
        self.assertEqual(
            {x["name"] for x in sysctls},
            {"net.ipv4.ip_forward", "net.ipv6.conf.all.forwarding",
             "net.ipv6.conf.eth6.accept_ra"},
        )

    def test_blocked_has_terminal_ipv6_reject_and_no_ipv6_forwarding(self):
        rules, sysctls = fw.commands(manifest("blocked", wan6=None))
        joined = [" ".join(rule) for rule in rules]
        self.assertTrue(any("ip6tables -A FAV6_wg0 -i wg0 -s fd12:3456:789a::/64 -j REJECT" == rule for rule in joined))
        self.assertFalse(any("-o eth6" in rule for rule in joined))
        self.assertEqual([x["name"] for x in sysctls], ["net.ipv4.ip_forward"])

    def test_anti_spoof_peer_isolation_input_and_unwanted_wan_are_explicit(self):
        joined = [" ".join(rule) for rule in fw.commands(manifest())[0]]
        self.assertTrue(any("-i wg0 ! -s 10.13.13.0/24 -j REJECT" in rule for rule in joined))
        self.assertTrue(any("-i wg0 -o wg0 -j REJECT" in rule for rule in joined))
        self.assertTrue(any("-i eth6 -o wg0" in rule and rule.endswith("-j REJECT") for rule in joined))
        self.assertIn("iptables -A FAV4I_wg0 -i wg0 -s 10.13.13.0/24 -p tcp --dport 2222 -j ACCEPT", joined)
        self.assertIn("ip6tables -A FAV6I_wg0 -i wg0 -s 2600:abcd:1234:5678::/64 -p tcp --dport 2222 -j ACCEPT", joined)
        self.assertNotIn("iptables -A FAV4I_wg0 -i wg0 -p tcp -j ACCEPT", joined)
        self.assertTrue(any("ip6tables -A FAV6I_wg0 -i wg0 -p ipv6-icmp -j ACCEPT" == rule for rule in joined))
        self.assertTrue(any("ip6tables -A FAV6I_wg0 -i wg0 -j REJECT" == rule for rule in joined))

    def test_invalid_wan_or_mode_fails_closed(self):
        bad = manifest(); bad["network"]["wan6"] = "bad device"
        with self.assertRaises(fw.FirewallError): fw.commands(bad)
        bad = manifest(); bad["network"]["ipv6Mode"] = "legacy"
        with self.assertRaises(fw.FirewallError): fw.commands(bad)
        for value in (None, 0, 65536, "22", True):
            bad = manifest(); bad["network"]["managementSshPort"] = value
            with self.assertRaises(fw.FirewallError): fw.commands(bad)

    def test_manifest_rejects_symlink_permissions_future_partial_and_identity(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "wg0" / "manifest.json"
            path.parent.mkdir()
            path.write_text(json.dumps(manifest()))
            os.chmod(path, 0o600)
            real_stat = os.stat(path)
            safe_stat = types.SimpleNamespace(st_uid=os.geteuid(), st_mode=stat.S_IFREG | 0o600)
            with mock.patch.object(fw.os, "stat", return_value=safe_stat):
                self.assertEqual(fw.secure_json(path, "wg0")["schemaVersion"], 2)
                with self.assertRaises(fw.FirewallError): fw.secure_json(path, "wg1")
            for mutate in (
                lambda x: x.update(schemaVersion=3),
                lambda x: x.pop("resources"),
            ):
                data = manifest(); mutate(data); path.write_text(json.dumps(data))
                with mock.patch.object(fw.os, "stat", return_value=safe_stat), self.assertRaises(fw.FirewallError):
                    fw.secure_json(path)
            target = Path(directory) / "target"; target.write_text("{}")
            path.unlink(); path.symlink_to(target)
            with self.assertRaises(fw.FirewallError): fw.secure_json(path)
            self.assertEqual(real_stat.st_mode & 0o777, 0o600)

    def test_resource_schema_rejects_arbitrary_manifest_argv(self):
        data = manifest(); rules, sysctls = fw.commands(data)
        data["resources"] = {"rules": rules + [["sh", "-c", "evil"]], "routes": [],
                             "sysctls": [dict(x, original="0") for x in sysctls]}
        with self.assertRaises(fw.FirewallError): fw.valid_owned(data)

    def test_partial_apply_rolls_back_owned_rules_and_sysctl(self):
        data = manifest("blocked", wan6=None)
        calls = []
        count = {"mutations": 0}

        def fake_run(argv, check=True):
            calls.append(argv)
            if argv[:2] == ["sysctl", "-n"]:
                return types.SimpleNamespace(returncode=0, stdout="0\n")
            if "-C" in argv or "-L" in argv:
                return types.SimpleNamespace(returncode=1, stdout="")
            if "-A" in argv or "-I" in argv or "-N" in argv:
                count["mutations"] += 1
                if count["mutations"] == 7:
                    raise fw.subprocess.CalledProcessError(1, argv)
            return types.SimpleNamespace(returncode=0, stdout="")

        with mock.patch.object(fw, "secure_json", return_value=data), \
                mock.patch.object(fw, "run", side_effect=fake_run), \
                mock.patch.object(fw, "atomic"):
            with self.assertRaises(fw.subprocess.CalledProcessError):
                fw.apply("manifest.json")
        self.assertTrue(any("-D" in call or "-X" in call for call in calls))
        self.assertIn(["sysctl", "-w", "net.ipv4.ip_forward=0"], calls)

    def test_remove_is_idempotent_after_wg_quick_postdown(self):
        data = manifest("blocked", wan6=None)
        with mock.patch.object(fw, "secure_json", return_value=data), \
                mock.patch.object(fw, "run") as run:
            fw.remove("manifest.json")
        run.assert_not_called()


if __name__ == "__main__":
    unittest.main()
