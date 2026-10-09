import 'package:fav/features/settings/application/error_history_notifier.dart';
import 'package:fav/features/settings/application/preferences_controller.dart';
import 'package:fav/features/settings/data/preferences_repository.dart';
import 'package:fav/features/settings/domain/user_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeRepo implements PreferencesRepository {
  UserPreferences current = UserPreferences.defaults;
  @override
  UserPreferences readSync() => current;
  @override
  Future<void> write(UserPreferences prefs) async {
    current = prefs;
  }
}

void main() {
  test('record appends most-recent-first and caps at 20', () async {
    final repo = _FakeRepo();
    final container = ProviderContainer(
      overrides: [
        preferencesRepositoryProvider.overrideWithValue(repo),
      ],
    );
    addTearDown(container.dispose);
    final ctrl = container.read(preferencesControllerProvider.notifier);
    final now = DateTime.utc(2026, 5, 29, 12);
    for (var i = 0; i < 25; i++) {
      await ctrl.recordError(
        'ERR-${i.toString().padLeft(2, '0')}',
        now.add(Duration(seconds: i)),
      );
    }
    final history = container.read(errorHistoryProvider);
    expect(history.length, 20);
    expect(history.first.codeId, 'ERR-24');
    expect(history.last.codeId, 'ERR-05');
  });

  test('record dedups consecutive duplicates', () async {
    final repo = _FakeRepo();
    final container = ProviderContainer(
      overrides: [
        preferencesRepositoryProvider.overrideWithValue(repo),
      ],
    );
    addTearDown(container.dispose);
    final ctrl = container.read(preferencesControllerProvider.notifier);
    final now = DateTime.utc(2026, 5, 29);
    await ctrl.recordError('ERR-CONN-01', now);
    await ctrl.recordError('ERR-CONN-01', now.add(const Duration(seconds: 1)));
    expect(container.read(errorHistoryProvider), hasLength(1));
  });
}
