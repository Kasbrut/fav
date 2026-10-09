// Shared error model. Every failure surfaced to the user maps to an
// [ErrorCode] from the spec catalogue (section 11.1). The UI shows a human
// message plus expandable technical detail; secrets must never reach [detail].

/// Catalogue of application error codes (`ERR-xx`, spec section 11.1).
enum ErrorCode {
  /// `ERR-CONN-01` — the host could not be reached.
  connHostUnreachable('ERR-CONN-01'),

  /// `ERR-CONN-02` — the SSH port did not respond.
  connSshPortClosed('ERR-CONN-02'),

  /// `ERR-CONN-03` — the address could not be resolved (DNS lookup failed),
  /// usually a typo in the IP or domain name.
  connAddressNotFound('ERR-CONN-03'),

  /// `ERR-AUTH-01` — wrong username or password.
  authInvalidCredentials('ERR-AUTH-01'),

  /// `ERR-AUTH-02` — the login user lacks the required sudo permissions.
  authNoSudo('ERR-AUTH-02'),

  /// `ERR-HOST-01` — the host key fingerprint changed (possible MITM).
  hostKeyMismatch('ERR-HOST-01'),

  /// `ERR-SYS-01` — the server runs an unsupported distribution.
  sysUnsupportedDistro('ERR-SYS-01'),

  /// `ERR-SYS-02` — the server kernel is too old for WireGuard.
  sysKernelTooOld('ERR-SYS-02'),

  /// `ERR-RUN-01` — the run is no longer present on the server.
  runLost('ERR-RUN-01'),

  /// `ERR-RUN-02` — an installation step failed.
  runStepFailed('ERR-RUN-02'),

  /// `ERR-LCK-01` — the anti-lockout sequence aborted the root SSH change.
  lockoutAborted('ERR-LCK-01'),

  /// `ERR-PWD-01` — the chosen password is too weak.
  passwordTooWeak('ERR-PWD-01'),

  /// `ERR-NET-01` — the server has no Internet access.
  netNoInternet('ERR-NET-01'),

  /// `ERR-SCRIPT-01` — the custom script failed `bash -n` validation.
  scriptInvalid('ERR-SCRIPT-01'),

  /// `ERR-TMO-01` — polling timed out with no response from the server.
  pollingTimeout('ERR-TMO-01'),

  /// `ERR-KEY-01` — the SSH key generated during hardening is no longer
  /// available in the device keystore, and password auth is disabled
  /// server-side. Requires manual recovery on the server.
  sshKeyUnavailable('ERR-KEY-01'),

  /// `ERR-KEY-02` — writing a user-supplied public key to the server's
  /// `authorized_keys` failed (the remote command returned non-zero).
  sshKeyDeployFailed('ERR-KEY-02'),

  /// `ERR-MON-01` — the monitor snapshot file failed to parse.
  monitorSnapshotInvalid('ERR-MON-01'),

  /// `ERR-MON-02` — the monitor agent is not installed on the server.
  monitorAgentNotInstalled('ERR-MON-02'),

  /// `ERR-MON-03` — pulling the snapshot/events over SSH failed.
  monitorPullFailed('ERR-MON-03'),

  /// `ERR-MON-04` — the snapshot is older than the staleness threshold;
  /// the agent timer is likely stopped.
  monitorAgentStale('ERR-MON-04'),

  /// `ERR-PEER-01` — the chosen peer label fails the validator.
  peerLabelInvalid('ERR-PEER-01'),

  /// `ERR-PEER-02` — the VPN subnet has no free host address; the user
  /// must revoke an unused peer to free one up.
  peerSubnetExhausted('ERR-PEER-02'),

  /// `ERR-PEER-03` — `wg set` accepted the change but the peer didn't
  /// appear on the interface (or the runtime apply itself failed); the
  /// server-side script has already rolled back the `[Peer]` block.
  peerApplyFailed('ERR-PEER-03'),

  /// `ERR-PEER-04` — the peer was not present on the server at revoke
  /// time. The app treats this as success for local cleanup, but the
  /// code is reported when the local removal also fails.
  peerNotFound('ERR-PEER-04'),

  /// `ERR-PEER-05` — the server returned a payload that does not match
  /// the expected sentinel-delimited envelope; the add may or may not
  /// have succeeded server-side.
  peerParseFailed('ERR-PEER-05'),

  /// `ERR-TRD-01` — the server teardown did not complete (a teardown step
  /// failed or the connection dropped before it finished).
  teardownFailed('ERR-TRD-01');

  /// Associates an [ErrorCode] with its stable [id].
  const ErrorCode(this.id);

  /// The stable `ERR-xx` identifier used in the spec, UI and logs.
  final String id;
}

/// Base class for expected, user-facing application failures.
class AppException implements Exception {
  /// Creates an [AppException] for the given [code].
  const AppException(this.code, {this.detail, this.cause});

  /// The error code from the catalogue (spec section 11.1).
  final ErrorCode code;

  /// Optional technical detail shown in the expandable error section.
  ///
  /// Must never contain secrets (passwords, private keys, PSKs).
  final String? detail;

  /// The underlying error that triggered this failure, if any.
  final Object? cause;

  @override
  String toString() {
    final suffix = detail == null ? '' : ': $detail';
    return 'AppException(${code.id}$suffix)';
  }
}
