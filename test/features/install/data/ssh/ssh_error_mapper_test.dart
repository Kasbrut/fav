import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:fav/core/errors/app_exception.dart';
import 'package:fav/features/install/data/ssh/ssh_error_mapper.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tests for the SSH error mapper.
void main() {
  test('connection refused maps to ERR-CONN-02', () {
    const error = SocketException('Connection refused');
    expect(mapSshError(error), ErrorCode.connSshPortClosed);
  });

  test('unreachable host maps to ERR-CONN-01', () {
    const error = SocketException('No route to host');
    expect(mapSshError(error), ErrorCode.connHostUnreachable);
  });

  test('an SSH auth failure maps to ERR-AUTH-01', () {
    expect(
      mapSshError(SSHAuthFailError('authentication failed')),
      ErrorCode.authInvalidCredentials,
    );
  });

  test('an unrelated error maps to a generic connection error', () {
    expect(mapSshError(StateError('boom')), ErrorCode.connHostUnreachable);
  });

  test('an SSH host-key error maps to ERR-HOST-01 (MITM safety net)', () {
    expect(
      mapSshError(SSHHostkeyError('host key changed')),
      ErrorCode.hostKeyMismatch,
    );
  });

  test('a host-key failure wrapped in an auth abort still maps to '
      'ERR-HOST-01 (M4)', () {
    // dartssh2 wraps every pre-auth transport error into SSHAuthAbortError:
    // a forged host key (signature verification failed) used to surface as
    // "invalid credentials", prompting the user to retype their password at
    // exactly the moment a MITM was being blocked.
    expect(
      mapSshError(
        SSHAuthAbortError(
          'Connection closed before authentication',
          SSHHostkeyError('Signature verification failed'),
        ),
      ),
      ErrorCode.hostKeyMismatch,
    );
  });

  test('a socket reset wrapped in an auth abort maps to ERR-CONN-01', () {
    expect(
      mapSshError(
        SSHAuthAbortError(
          'Connection closed before authentication',
          SSHSocketError(const SocketException('Connection reset by peer')),
        ),
      ),
      ErrorCode.connHostUnreachable,
    );
  });

  test('an auth timeout maps to ERR-CONN-01, not invalid credentials', () {
    expect(
      mapSshError(SSHAuthAbortError('Authentication timed out')),
      ErrorCode.connHostUnreachable,
    );
  });

  group('a failed DNS lookup maps to ERR-CONN-03 (address not found)', () {
    // The wording differs across platforms; the mapper must catch them all.
    const messages = [
      'Failed host lookup: example.invalid',
      'nodename nor servname provided, or not known',
      'Name or service not known',
      'Temporary failure in name resolution',
      'No address associated with hostname',
      'getaddrinfo failed',
    ];
    for (final message in messages) {
      test('"$message"', () {
        expect(
          mapSshError(SocketException(message)),
          ErrorCode.connAddressNotFound,
        );
      });
    }
  });

  test('a lookup failure reported via osError still maps to ERR-CONN-03', () {
    const error = SocketException(
      'Connection failed',
      osError: OSError('Name or service not known', 8),
    );
    expect(mapSshError(error), ErrorCode.connAddressNotFound);
  });
}
