import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:fav/core/errors/app_exception.dart';

/// Maps a low-level SSH or socket [error] to an [ErrorCode] (spec §11.1).
///
/// Host-key mismatches are normally surfaced by the host key verifier; the
/// `SSHHostkeyError` case here is a safety net against a future regression.
ErrorCode mapSshError(Object error) {
  if (error is SSHHostkeyError) {
    return ErrorCode.hostKeyMismatch;
  }
  // dartssh2 wraps every pre-auth transport failure into SSHAuthAbortError
  // (a subclass of SSHAuthError): without unwrapping, a forged host key
  // ("Signature verification failed") would surface as invalid credentials
  // and invite the user to retype their password at exactly the moment a
  // MITM was being blocked (security audit M4).
  if (error is SSHAuthAbortError) {
    final reason = error.reason;
    // dartssh2 documents auth-abort as authentication being interrupted by
    // another failure (for example a network reset), not rejected
    // credentials. Preserve a wrapped transport/host-key classification;
    // an abort without a reason is typically the library auth timeout.
    return reason == null ? ErrorCode.connHostUnreachable : mapSshError(reason);
  }
  if (error is SSHSocketError) {
    return mapSshError(error.error);
  }
  if (error is SocketException) {
    final message = (error.osError?.message ?? error.message).toLowerCase();
    if (message.contains('refused')) {
      return ErrorCode.connSshPortClosed;
    }
    // A failed DNS lookup means the address itself is wrong (a typo in the IP
    // or domain), which is distinct from a reachable-but-down host. The exact
    // wording varies by platform (Dart, glibc, BSD/macOS, Windows).
    const lookupFailures = [
      'failed host lookup',
      'nodename nor servname',
      'name or service not known',
      'temporary failure in name resolution',
      'no address associated with hostname',
      'getaddrinfo',
    ];
    if (lookupFailures.any(message.contains)) {
      return ErrorCode.connAddressNotFound;
    }
    return ErrorCode.connHostUnreachable;
  }
  if (error is SSHAuthFailError) {
    return ErrorCode.authInvalidCredentials;
  }
  return ErrorCode.connHostUnreachable;
}
