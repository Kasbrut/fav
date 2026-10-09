import 'package:fav/features/settings/data/device_auth_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';

/// [LocalAuthentication] stub whose every call throws the given exception.
class _ThrowingLocalAuth implements LocalAuthentication {
  _ThrowingLocalAuth(this.code);

  final LocalAuthExceptionCode code;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw LocalAuthException(code: code);
}

void main() {
  test('maps plugin errors to failed (never throws into the UI)', () async {
    final service = DeviceAuthService(
      auth: _ThrowingLocalAuth(LocalAuthExceptionCode.uiUnavailable),
    );
    expect(await service.isAvailable(), isFalse);
    expect(await service.authenticate('reason'), DeviceAuthOutcome.failed);
  });

  test('maps a missing device credential to noCredentials', () async {
    // The one fail-open case: both platforms report "nothing enrolled" as
    // LocalAuthExceptionCode.noCredentialsSet.
    final service = DeviceAuthService(
      auth: _ThrowingLocalAuth(LocalAuthExceptionCode.noCredentialsSet),
    );
    expect(
      await service.authenticate('reason'),
      DeviceAuthOutcome.noCredentials,
    );
  });
}
