import 'package:fav/features/settings/application/app_reset_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'wipe initializes Hive, deletes the keystore first, then all 6 boxes',
    () async {
      final calls = <String>[];

      final service = AppResetService(
        ensureInitialized: () async {
          calls.add('init');
        },
        closeAllBoxes: () async {
          calls.add('closeAllBoxes');
        },
        deleteBoxFromDisk: (name) async {
          calls.add('delete:$name');
        },
        deleteAllSecureEntries: () async {
          calls.add('secure');
        },
        clearLogBuffer: () {
          calls.add('clearLogs');
        },
      );

      await service.wipe();

      expect(calls.first, 'init');
      expect(calls[1], 'closeAllBoxes');
      // The keystore entries go before any box file (security audit H3): a
      // partial failure must leave key-less ciphertext, never orphaned keys.
      expect(calls[2], 'secure');
      // The in-memory log buffer names the erased servers and is exportable
      // through the bug-report flow: it goes with them (security audit M4).
      expect(calls[3], 'clearLogs');
      expect(
        calls.sublist(3),
        containsAll([
          'delete:servers',
          'delete:runs',
          'delete:scripts',
          'delete:monitoring_events',
          'delete:peers',
          'delete:preferences',
        ]),
      );
    },
  );

  test(
    'a failing secure delete aborts before any box file is removed (H3)',
    () async {
      final calls = <String>[];
      final service = AppResetService(
        ensureInitialized: () async {},
        closeAllBoxes: () async {},
        deleteBoxFromDisk: (name) async {
          calls.add('delete:$name');
        },
        deleteAllSecureEntries: () async {
          throw StateError('keystore unavailable');
        },
      );

      await expectLater(service.wipe(), throwsA(isA<StateError>()));
      // Boxes intact: the erase can be retried from a consistent state.
      expect(calls, isEmpty);
    },
  );

  test(
    'a failing box delete still deletes the others and reports it (H3)',
    () async {
      final calls = <String>[];
      final service = AppResetService(
        ensureInitialized: () async {},
        closeAllBoxes: () async {},
        deleteBoxFromDisk: (name) async {
          if (name == 'runs') {
            throw StateError('locked');
          }
          calls.add('delete:$name');
        },
        deleteAllSecureEntries: () async {
          calls.add('secure');
        },
      );

      Object? thrown;
      try {
        await service.wipe();
      } on Object catch (error) {
        thrown = error;
      }
      expect(thrown, isNotNull, reason: 'the partial failure must surface');
      expect(calls, contains('secure'));
      expect(calls, contains('delete:servers'));
      expect(calls, contains('delete:preferences'));
    },
  );

  test('a failing Hive init does not block the erase (M1)', () async {
    final calls = <String>[];
    final service = AppResetService(
      ensureInitialized: () async {
        throw StateError('no binding');
      },
      closeAllBoxes: () async {},
      deleteBoxFromDisk: (name) async {
        calls.add('delete:$name');
      },
      deleteAllSecureEntries: () async {
        calls.add('secure');
      },
    );

    // The per-box deletes may fail without init, but the keystore sweep must
    // still run — it does not depend on Hive at all.
    try {
      await service.wipe();
    } on Object {
      // Acceptable: partial failures surface.
    }
    expect(calls, contains('secure'));
  });

  test('wipe surfaces close errors without blocking the erase', () async {
    final calls = <String>[];
    final service = AppResetService(
      ensureInitialized: () async {},
      closeAllBoxes: () async {
        throw StateError('forced');
      },
      deleteBoxFromDisk: (name) async {
        calls.add('delete:$name');
      },
      deleteAllSecureEntries: () async {
        calls.add('secure');
      },
    );
    await service.wipe();
    expect(calls, contains('secure'));
    expect(calls, contains('delete:servers'));
  });
}
