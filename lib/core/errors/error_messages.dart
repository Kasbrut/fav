import 'package:fav/core/errors/app_exception.dart';
import 'package:fav/l10n/app_localizations.dart';

/// Returns the human-readable, localized message for [code] (spec §11.1).
///
/// [stepName] supplies the failed step name for [ErrorCode.runStepFailed] and
/// is ignored by every other code.
String localizedErrorMessage(
  AppLocalizations l10n,
  ErrorCode code, {
  String? stepName,
}) {
  return switch (code) {
    ErrorCode.connHostUnreachable => l10n.errConnHostUnreachable,
    ErrorCode.connSshPortClosed => l10n.errConnSshPortClosed,
    ErrorCode.connAddressNotFound => l10n.errConnAddressNotFound,
    ErrorCode.authInvalidCredentials => l10n.errAuthInvalidCredentials,
    ErrorCode.authNoSudo => l10n.errAuthNoSudo,
    ErrorCode.hostKeyMismatch => l10n.errHostKeyMismatch,
    ErrorCode.sysUnsupportedDistro => l10n.errSysUnsupportedDistro,
    ErrorCode.sysKernelTooOld => l10n.errSysKernelTooOld,
    ErrorCode.runLost => l10n.errRunLost,
    ErrorCode.runStepFailed => l10n.errRunStepFailed(stepName ?? ''),
    ErrorCode.lockoutAborted => l10n.errLockoutAborted,
    ErrorCode.passwordTooWeak => l10n.errPasswordTooWeak,
    ErrorCode.netNoInternet => l10n.errNetNoInternet,
    ErrorCode.scriptInvalid => l10n.errScriptInvalid,
    ErrorCode.pollingTimeout => l10n.errPollingTimeout,
    ErrorCode.sshKeyUnavailable => l10n.errSshKeyUnavailable,
    ErrorCode.sshKeyDeployFailed => l10n.errSshKeyDeployFailed,
    ErrorCode.monitorSnapshotInvalid => l10n.errMonitorSnapshotInvalid,
    ErrorCode.monitorAgentNotInstalled => l10n.errMonitorAgentNotInstalled,
    ErrorCode.monitorPullFailed => l10n.errMonitorPullFailed,
    ErrorCode.monitorAgentStale => l10n.errMonitorAgentStale,
    ErrorCode.peerLabelInvalid => l10n.errPeerLabelInvalid,
    ErrorCode.peerSubnetExhausted => l10n.errPeerSubnetExhausted,
    ErrorCode.peerApplyFailed => l10n.errPeerApplyFailed,
    ErrorCode.peerNotFound => l10n.errPeerNotFound,
    ErrorCode.peerParseFailed => l10n.errPeerParseFailed,
    ErrorCode.teardownFailed => l10n.errTeardownFailed,
  };
}

/// Returns the localized "why this happened" text for [code] (used on the
/// troubleshooting card at `/help/errors/:code`). The switch is exhaustive
/// by design: adding a new [ErrorCode] without extending this function is
/// a compile error.
String localizedErrorCause(AppLocalizations l10n, ErrorCode code) {
  return switch (code) {
    ErrorCode.connHostUnreachable => l10n.errConnHostUnreachableCause,
    ErrorCode.connSshPortClosed => l10n.errConnSshPortClosedCause,
    ErrorCode.connAddressNotFound => l10n.errConnAddressNotFoundCause,
    ErrorCode.authInvalidCredentials => l10n.errAuthInvalidCredentialsCause,
    ErrorCode.authNoSudo => l10n.errAuthNoSudoCause,
    ErrorCode.hostKeyMismatch => l10n.errHostKeyMismatchCause,
    ErrorCode.sysUnsupportedDistro => l10n.errSysUnsupportedDistroCause,
    ErrorCode.sysKernelTooOld => l10n.errSysKernelTooOldCause,
    ErrorCode.runLost => l10n.errRunLostCause,
    ErrorCode.runStepFailed => l10n.errRunStepFailedCause,
    ErrorCode.lockoutAborted => l10n.errLockoutAbortedCause,
    ErrorCode.passwordTooWeak => l10n.errPasswordTooWeakCause,
    ErrorCode.netNoInternet => l10n.errNetNoInternetCause,
    ErrorCode.scriptInvalid => l10n.errScriptInvalidCause,
    ErrorCode.pollingTimeout => l10n.errPollingTimeoutCause,
    ErrorCode.sshKeyUnavailable => l10n.errSshKeyUnavailableCause,
    ErrorCode.sshKeyDeployFailed => l10n.errSshKeyDeployFailedCause,
    ErrorCode.monitorSnapshotInvalid => l10n.errMonitorSnapshotInvalidCause,
    ErrorCode.monitorAgentNotInstalled => l10n.errMonitorAgentNotInstalledCause,
    ErrorCode.monitorPullFailed => l10n.errMonitorPullFailedCause,
    ErrorCode.monitorAgentStale => l10n.errMonitorAgentStaleCause,
    ErrorCode.peerLabelInvalid => l10n.errPeerLabelInvalidCause,
    ErrorCode.peerSubnetExhausted => l10n.errPeerSubnetExhaustedCause,
    ErrorCode.peerApplyFailed => l10n.errPeerApplyFailedCause,
    ErrorCode.peerNotFound => l10n.errPeerNotFoundCause,
    ErrorCode.peerParseFailed => l10n.errPeerParseFailedCause,
    ErrorCode.teardownFailed => l10n.errTeardownFailedCause,
  };
}

/// Returns the localized "how to fix" text for [code]. Exhaustive switch.
String localizedErrorFix(AppLocalizations l10n, ErrorCode code) {
  return switch (code) {
    ErrorCode.connHostUnreachable => l10n.errConnHostUnreachableFix,
    ErrorCode.connSshPortClosed => l10n.errConnSshPortClosedFix,
    ErrorCode.connAddressNotFound => l10n.errConnAddressNotFoundFix,
    ErrorCode.authInvalidCredentials => l10n.errAuthInvalidCredentialsFix,
    ErrorCode.authNoSudo => l10n.errAuthNoSudoFix,
    ErrorCode.hostKeyMismatch => l10n.errHostKeyMismatchFix,
    ErrorCode.sysUnsupportedDistro => l10n.errSysUnsupportedDistroFix,
    ErrorCode.sysKernelTooOld => l10n.errSysKernelTooOldFix,
    ErrorCode.runLost => l10n.errRunLostFix,
    ErrorCode.runStepFailed => l10n.errRunStepFailedFix,
    ErrorCode.lockoutAborted => l10n.errLockoutAbortedFix,
    ErrorCode.passwordTooWeak => l10n.errPasswordTooWeakFix,
    ErrorCode.netNoInternet => l10n.errNetNoInternetFix,
    ErrorCode.scriptInvalid => l10n.errScriptInvalidFix,
    ErrorCode.pollingTimeout => l10n.errPollingTimeoutFix,
    ErrorCode.sshKeyUnavailable => l10n.errSshKeyUnavailableFix,
    ErrorCode.sshKeyDeployFailed => l10n.errSshKeyDeployFailedFix,
    ErrorCode.monitorSnapshotInvalid => l10n.errMonitorSnapshotInvalidFix,
    ErrorCode.monitorAgentNotInstalled => l10n.errMonitorAgentNotInstalledFix,
    ErrorCode.monitorPullFailed => l10n.errMonitorPullFailedFix,
    ErrorCode.monitorAgentStale => l10n.errMonitorAgentStaleFix,
    ErrorCode.peerLabelInvalid => l10n.errPeerLabelInvalidFix,
    ErrorCode.peerSubnetExhausted => l10n.errPeerSubnetExhaustedFix,
    ErrorCode.peerApplyFailed => l10n.errPeerApplyFailedFix,
    ErrorCode.peerNotFound => l10n.errPeerNotFoundFix,
    ErrorCode.peerParseFailed => l10n.errPeerParseFailedFix,
    ErrorCode.teardownFailed => l10n.errTeardownFailedFix,
  };
}
