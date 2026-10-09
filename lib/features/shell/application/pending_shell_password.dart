import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One-shot in-memory handoff of the SSH login password from the screen
/// that prompted it to the shell screen.
///
/// The password must never travel as a go_router `extra`: extras are
/// JSON-encoded into the engine's route-information state on every route
/// report, one `restorationScopeId` away from being persisted to disk
/// (spec §10 — never persist login passwords; audit MEDIUM-2).
class PendingShellPasswords {
  final Map<String, String> _byServerId = {};

  /// Stages [password] for [serverId] until the shell screen takes it.
  void put(String serverId, String password) =>
      _byServerId[serverId] = password;

  /// Removes and returns the staged password for [serverId], if any.
  String? take(String serverId) => _byServerId.remove(serverId);
}

/// Provides the app-wide [PendingShellPasswords] holder.
final Provider<PendingShellPasswords> pendingShellPasswordsProvider =
    Provider<PendingShellPasswords>((ref) => PendingShellPasswords());
