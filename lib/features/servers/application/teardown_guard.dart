import 'package:fav/features/servers/domain/server.dart';

/// Whether tearing down [server] would strip the last SSH access path,
/// risking lockout — and therefore the modal must surface an add-key option
/// (and the controller must refuse) unless the user also re-opens SSH.
///
/// Risk iff ALL hold: FAV's app key will be removed (`sshKeyId != null`); the
/// recorded install hardened SSH so password login is off
/// (`installation.hardeningApplied`); the operator registered no own keys
/// (`userAuthorizedKeys` empty); and "re-open SSH" is not selected.
bool teardownWouldLockOut({
  required Server server,
  required bool reopenSsh,
}) {
  if (reopenSsh) {
    return false;
  }
  final removesAppKey = server.sshKeyId != null;
  final hardened = server.installation?.hardeningApplied ?? false;
  final noOwnKeys = server.userAuthorizedKeys.isEmpty;
  return removesAppKey && hardened && noOwnKeys;
}
