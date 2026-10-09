import importlib.util
import json
import os
import tempfile
import types
import unittest
from pathlib import Path
from unittest import mock


SCRIPT = Path(__file__).parents[2] / "lib/assets/scripts/lib/network_probe.py"
SPEC = importlib.util.spec_from_file_location("network_probe", SCRIPT)
PROBE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PROBE)


class ProbeHarness:
    def __init__(self, ping="success", wan4="ens4", wan6="ens6", fail_on=None):
        self.ping = ping
        self.wan4 = wan4
        self.wan6 = wan6
        self.fail_on = fail_on
        self.calls = []

    def run(self, *args, check=True):
        self.calls.append(args)
        joined = " ".join(args)
        if self.fail_on and self.fail_on in joined:
            raise PROBE.ProbeError("injected")
        if args[0] in ("iptables", "ip6tables") and args[1] == "--version":
            return types.SimpleNamespace(returncode=0, stdout="iptables v1.8 (nf_tables)", stderr="")
        if args[:4] == ("ip", "-4", "route", "show"):
            text = f"default via 192.0.2.1 dev {self.wan4}\n" if self.wan4 else ""
            return types.SimpleNamespace(returncode=0, stdout=text, stderr="")
        if args[:4] == ("ip", "-6", "route", "show"):
            text = f"default via fe80::1 dev {self.wan6}\n" if self.wan6 else ""
            return types.SimpleNamespace(returncode=0, stdout=text, stderr="")
        if args[:3] == ("ip", "netns", "list"):
            return types.SimpleNamespace(returncode=0, stdout="", stderr="")
        if args[:4] == ("ip", "link", "show", "dev"):
            return types.SimpleNamespace(returncode=1, stdout="", stderr="")
        if "ping" in args:
            if self.ping == "success":
                return types.SimpleNamespace(returncode=0, stdout="1 packets transmitted, 1 received", stderr="")
            if self.ping == "mismatch":
                return types.SimpleNamespace(returncode=0, stdout="unrelated output", stderr="")
            return types.SimpleNamespace(returncode=1, stdout="0 received", stderr="")
        return types.SimpleNamespace(returncode=0, stdout="", stderr="")


class NetworkProbeTest(unittest.TestCase):
    def invoke(self, *, routed=True, target=True, ping="success", wan6="ens6", fail_on=None):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        result_path = str(Path(directory.name) / "network-result.json")
        environment = {
            "FAV_CONFIG_VERSION": "2",
            "FAV_INSTALLATION_ID": "installation-1",
            "FAV_OPERATION_ID": "operation-1",
            "VPN_SUBNET": "10.13.13.0/24",
            "VPN_IPV6_ULA_SUBNET": "fd12:3456:789a::/64",
            "VPN_IPV6_ROUTED_SUBNET": "2001:4860:1234:1::/64" if routed else "",
            "IPV6_PROBE_TARGET": "2001:4860:4860::8888" if target else "",
            "NETWORK_RESULT_PATH": result_path,
        }
        harness = ProbeHarness(ping=ping, wan6=wan6, fail_on=fail_on)
        self.last_calls = harness.calls
        real_open = open

        def fake_open(path, *args, **kwargs):
            if path.endswith("disable_ipv6"):
                return mock.mock_open(read_data="0").return_value
            if path.endswith("forwarding"):
                return mock.mock_open(read_data="1").return_value
            return real_open(path, *args, **kwargs)

        with mock.patch.dict(os.environ, environment, clear=True), mock.patch.object(PROBE, "run", harness.run), mock.patch("builtins.open", fake_open):
            PROBE.main()
        return json.loads(Path(result_path).read_text()), harness.calls

    def test_supported_uses_attested_prefix_and_separate_wans(self):
        result, calls = self.invoke()
        self.assertEqual(result["capability"]["status"], "supported")
        self.assertEqual(result["network"]["ipv6Mode"], "routed")
        self.assertEqual(result["network"]["wan4"], "ens4")
        self.assertEqual(result["network"]["wan6"], "ens6")
        self.assertNotIn("eth0", json.dumps(result))
        self.assertTrue(any(call[:3] == ("ip", "netns", "delete") for call in calls))
        self.assertTrue(any(call[:3] == ("ip", "link", "delete") for call in calls))

    def test_missing_prefix_is_unavailable_and_blocked(self):
        result, _ = self.invoke(routed=False, target=False)
        self.assertEqual(result["capability"]["status"], "unavailable")
        self.assertEqual(result["capability"]["reason"], "no_delegated_prefix")
        self.assertEqual(result["network"]["ipv6Mode"], "blocked")

    def test_missing_target_timeout_and_uncorrelated_reply_are_unknown(self):
        for target, ping, reason in (
            (False, "success", "probe_target_missing"),
            (True, "timeout", "probe_timeout"),
            (True, "mismatch", "probe_reply_mismatch"),
        ):
            with self.subTest(reason=reason):
                result, _ = self.invoke(target=target, ping=ping)
                self.assertEqual(result["capability"]["status"], "unknown")
                self.assertEqual(result["capability"]["reason"], reason)
                self.assertEqual(result["network"]["ipv6Mode"], "blocked")

    def test_missing_ipv6_route_is_unavailable(self):
        result, _ = self.invoke(wan6=None)
        self.assertEqual(result["capability"]["status"], "unavailable")
        self.assertEqual(result["capability"]["reason"], "no_ipv6_default_route")

    def test_cleanup_runs_when_probe_setup_fails(self):
        with self.assertRaises(PROBE.ProbeError):
            self.invoke(fail_on="addr add")
        self.assertTrue(
            any(call[:3] == ("ip", "netns", "delete") for call in self.last_calls)
        )


if __name__ == "__main__":
    unittest.main()
