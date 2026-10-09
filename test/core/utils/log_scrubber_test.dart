import 'package:fav/core/utils/log_scrubber.dart';
import 'package:flutter_test/flutter_test.dart';

/// The scrubbed log lands in a PUBLIC GitHub issue: IPs, hostnames and
/// usernames identify the user's server and must be masked, matching the
/// bar the extended-diagnostic allowlist sets (it deliberately excludes all
/// three). Secrets are already redacted upstream by the log buffer.
void main() {
  group('scrubLogLine', () {
    test('masks IPv4 addresses, keeping the port readable', () {
      expect(
        scrubLogLine('SSH connect: 198.51.100.1:22 reachable'),
        'SSH connect: <ip>:22 reachable',
      );
      expect(
        scrubLogLine('endpoint 203.0.113.5 latency ok'),
        'endpoint <ip> latency ok',
      );
    });

    test('masks the username in user@host references', () {
      expect(
        scrubLogLine('SSH connect: favops@198.51.100.1:22 (auth: key)'),
        'SSH connect: <user>@<ip>:22 (auth: key)',
      );
      expect(
        scrubLogLine('deploying for root@vpn.example.org now'),
        'deploying for <user>@<host> now',
      );
    });

    test('masks bare domain names', () {
      expect(
        scrubLogLine('resolving vpn.example.org failed'),
        'resolving <host> failed',
      );
      expect(
        scrubLogLine('probe of my-server.dyndns.example.com done'),
        'probe of <host> done',
      );
    });

    test('leaves file names and unit names untouched', () {
      const line = 'uploaded 30_generate_keys.sh; wg-monitor.service enabled';
      expect(scrubLogLine(line), line);
      const conf = 'wrote wg7.conf and peers-state.json';
      expect(scrubLogLine(conf), conf);
    });

    test('keeps the run state/exit/pid file names (log vocabulary)', () {
      // Seen in a real device report (2026-09-08): `<run-id>.state` etc.
      // were masked as `<host>`, which confuses the reader and protects
      // nothing — the same UUID appears unmasked in /opt paths nearby.
      const dir = '/var/lib/wg-installer';
      const runId = '453356e1-4b13-4ad3-80d3-876b337540e8';
      const line =
          "cat '$dir/$runId.state'; echo '---WG-EXIT---'; "
          "cat '$dir/$runId.exit'; "
          "echo pid > '$dir/$runId.pid'";
      expect(scrubLogLine(line), line);
    });

    test('scrubLog joins buffered lines and scrubs each', () {
      final text = scrubLog([
        'connecting to 10.0.0.5',
        'plain line',
      ]);
      expect(text, 'connecting to <ip>\nplain line');
    });

    test('masks host-key fingerprints (audit H1)', () {
      // A published SHA-256 host-key fingerprint is a Censys/Shodan lookup
      // key straight back to the IP the scrubber just masked.
      const line =
          'Host key unknown for <ip>:22 — TOFU confirmation needed '
          '(ssh-ed25519 sha256 AbCdEfGh01234567890123456789012345678901+/x)';
      final scrubbed = scrubLogLine(line);
      expect(scrubbed, isNot(contains('AbCdEfGh')));
      expect(scrubbed, contains('<fingerprint>'));
    });

    test('masks identifying env values in command traces (H2/M2)', () {
      expect(
        scrubLogLine(
          "sudo -- env NEW_USERNAME='favops' WG_INTERFACE='wg7' "
          'bash install_monitor.sh',
        ),
        contains("NEW_USERNAME='<masked>'"),
      );
      expect(
        scrubLogLine("env PEER_LABEL='Example phone' DNS='1.1.1.1' bash x"),
        allOf(
          contains("PEER_LABEL='<masked>'"),
          isNot(contains('Example phone')),
        ),
      );
      // The interface name is not identifying and keeps triage value.
      expect(
        scrubLogLine("env WG_INTERFACE='wg7' bash x"),
        contains("WG_INTERFACE='wg7'"),
      );
    });

    test('masks the chown target username (H2)', () {
      expect(
        scrubLogLine("sh -c 'chown -R 'favops' /opt/wg-installer/runs/x'"),
        contains("chown -R '<user>'"),
      );
    });

    test('masks IPv6 addresses but not ISO timestamps (M1)', () {
      expect(
        scrubLogLine('endpoint 2001:db8::1 port 51999'),
        'endpoint <ip> port 51999',
      );
      expect(
        scrubLogLine('link-local fe80::1%eth0 seen'),
        'link-local <ip> seen',
      );
      // Buffer lines start with an ISO timestamp: colon-separated digit
      // groups must never be mistaken for an address.
      const stamped = '[2026-08-19T12:00:00.000] INFO poll ok';
      expect(scrubLogLine(stamped), stamped);
    });
  });
}
