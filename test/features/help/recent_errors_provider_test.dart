import 'package:fav/core/errors/app_exception.dart';
import 'package:fav/features/help/application/recent_errors_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('starts empty', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(c.read(recentErrorsProvider), isEmpty);
  });

  test('keeps at most 3 entries, most recent first', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.read(recentErrorsProvider.notifier)
      ..record(ErrorCode.connHostUnreachable)
      ..record(ErrorCode.authNoSudo)
      ..record(ErrorCode.hostKeyMismatch)
      ..record(ErrorCode.netNoInternet);

    expect(c.read(recentErrorsProvider), [
      'ERR-NET-01',
      'ERR-HOST-01',
      'ERR-AUTH-02',
    ]);
  });

  test('does not record the same code twice in a row', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.read(recentErrorsProvider.notifier)
      ..record(ErrorCode.connHostUnreachable)
      ..record(ErrorCode.connHostUnreachable);
    expect(c.read(recentErrorsProvider), ['ERR-CONN-01']);
  });
}
