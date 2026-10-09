import 'dart:async';

import 'package:fav/core/persistence/secure_store.dart';
import 'package:fav/core/utils/app_logger.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

/// The full set of box names the app owns. Adding a 7th box later requires
/// extending this list so `wipe()` knows to delete it.
const List<String> appBoxNames = [
  'servers',
  'runs',
  'scripts',
  'monitoring_events',
  'peers',
  'preferences',
];

/// Wipes all local app data: Hive boxes + secure storage entries.
///
/// The function-typed dependencies allow tests to stub Hive and the
/// secure-storage bulk delete (the `SecureStore` interface doesn't expose
/// a `deleteAll`; the production call site provides the hardened backend's
/// `deleteAll`).
class AppResetService {
  /// Creates the service.
  AppResetService({
    required this.deleteAllSecureEntries,
    Future<void> Function()? ensureInitialized,
    Future<void> Function()? closeAllBoxes,
    Future<void> Function(String name)? deleteBoxFromDisk,
    void Function()? clearLogBuffer,
  }) : _ensureInitialized = ensureInitialized ?? Hive.initFlutter,
       _closeAllBoxes = closeAllBoxes ?? Hive.close,
       _deleteBoxFromDisk = deleteBoxFromDisk ?? Hive.deleteBoxFromDisk,
       _clearLogBuffer = clearLogBuffer ?? appLogBuffer.clear;

  /// Closure that deletes every entry from the OS-backed secure storage.
  final Future<void> Function() deleteAllSecureEntries;

  final Future<void> Function() _ensureInitialized;
  final Future<void> Function() _closeAllBoxes;
  final Future<void> Function(String name) _deleteBoxFromDisk;
  final void Function() _clearLogBuffer;

  /// Performs the wipe in this order:
  /// 1. Initialize Hive if needed — on the boot-failure recovery path (M10)
  ///    the boot may have died before `Hive.initFlutter()`, and the box
  ///    deletes would throw on a null home path (security audit M1).
  /// 2. Close all boxes (release file locks). Best-effort.
  /// 3. Delete every secure storage entry FIRST (security audit H3): if a
  ///    later step fails, the residue is encrypted box files whose key is
  ///    gone — unreadable ciphertext, acceptable. The inverse order could
  ///    leave every private key orphaned in the keystore while the app
  ///    looks freshly wiped. A failure here aborts with the boxes intact,
  ///    so the erase can be retried from a consistent state.
  /// 4. Delete each box file, best-effort; failures are collected and
  ///    re-thrown together at the end.
  Future<void> wipe() async {
    try {
      await _ensureInitialized();
    } on Object {
      // Best-effort: the per-box deletes below surface any real failure,
      // and the keystore sweep does not depend on Hive at all.
    }
    try {
      await _closeAllBoxes();
    } on Object {
      // Best-effort: an unopened or broken box set must not block the erase.
    }
    await deleteAllSecureEntries();
    // Past the point of no return: the in-memory log buffer names the
    // erased servers (hosts, usernames) and is exportable through the
    // bug-report flow — it goes with them (security audit M4).
    _clearLogBuffer();
    final failures = <String>[];
    for (final name in appBoxNames) {
      try {
        await _deleteBoxFromDisk(name);
      } on Object catch (error) {
        // Type-only: never propagate raw platform messages from here.
        failures.add('$name (${error.runtimeType})');
      }
    }
    if (failures.isNotEmpty) {
      throw StateError(
        'some local files could not be deleted: ${failures.join(', ')}',
      );
    }
  }
}

/// Provides the production [AppResetService]. The bulk delete goes through
/// the same hardened storage backend the app writes with, so `deleteAll`
/// sweeps exactly the store that holds the secrets (security audit L1).
final Provider<AppResetService> appResetServiceProvider =
    Provider<AppResetService>(
      (ref) => AppResetService(
        deleteAllSecureEntries: kSecureStorageBackend.deleteAll,
      ),
    );
