import 'dart:convert';

import 'package:fav/core/utils/validators.dart';

import 'package:fav/features/install/domain/advanced_options.dart';
import 'package:fav/features/install/domain/new_user_spec.dart';

/// Renders the `config.env` file uploaded to the server for a run.
///
/// The orchestrator sources this file as bash, so every value is escaped for
/// a double-quoted bash string (M6 security audit). The rendered text holds
/// `NEW_PASSWORD` and must never be logged.
class ConfigEnvWriter {
  /// Creates a [ConfigEnvWriter].
  const ConfigEnvWriter();

  /// Renders the v2 `config.env` content for [options] and an optional
  /// [newUser].
  ///
  /// [sshPublicKey], when provided, is the OpenSSH `authorized_keys` line of
  /// the app-generated Ed25519 key. Since M15-T1 the orchestrator consumes
  /// it unconditionally via `25_deploy_app_key`, regardless of hardening,
  /// so post-install operations can authenticate by key.
  ///
  /// `options.userAuthorizedKeys` are the user-supplied public keys; they are
  /// emitted as a single base64 value (`USER_AUTHORIZED_KEYS_B64`) because the
  /// multi-line block cannot be represented as one `KEY="value"` line, and the
  /// `_escape` guard below rejects the newlines that join them. Module
  /// `26_deploy_user_keys` decodes and deploys them.
  ///
  /// Throws an [ArgumentError] when a value contains a control character: such
  /// a value cannot be represented as one safe `KEY="value"` line.
  /// [loginUser] is the SSH login user; when no [newUser] is created it becomes
  /// `NEW_USERNAME` so the app key (and user keys) deploy to the user the app
  /// will connect as post-install — needed when installing as an existing
  /// non-root sudoer. Ignored (key goes to the new user, else root) otherwise.
  String render({
    required AdvancedOptions options,
    required String installationId,
    required String operationId,
    required String ipv6UlaSubnet,
    NewUserSpec? newUser,
    String? sshPublicKey,
    String? loginUser,
    int sshPort = 22,
  }) {
    if (!isValidVpnSubnet(options.vpnSubnet)) {
      throw ArgumentError('VPN subnet must be a canonical IPv4 /24 network');
    }
    if (!isValidPort('$sshPort')) {
      throw ArgumentError('SSH port must be between 1 and 65535');
    }
    if (!_isSafeIdentity(installationId) ||
        !_isSafeIdentity(operationId) ||
        !isValidVpnSubnetV6(ipv6UlaSubnet)) {
      throw ArgumentError('invalid v2 provisioning request');
    }
    final routed = options.delegatedIpv6Prefix ?? '';
    if (routed.isNotEmpty && !isValidVpnSubnetV6(routed)) {
      throw ArgumentError('routed IPv6 subnet must be a canonical /64');
    }
    final userKeys = options.userAuthorizedKeys;
    final userKeysB64 = userKeys.isEmpty
        ? ''
        : base64.encode(utf8.encode(userKeys.join('\n')));
    final entries = <String, String>{
      'CREATE_USER': newUser != null ? 'true' : 'false',
      // The app key / user keys deploy to NEW_USERNAME (`${NEW_USERNAME:-root}`
      // in the modules). When not creating a user, target the login user so a
      // non-root sudoer install lands the key on the account the app uses.
      'NEW_USERNAME': newUser?.username ?? loginUser ?? '',
      'NEW_PASSWORD': newUser?.password ?? '',
      // Root SSH is disabled post-install by the app-driven AntiLockoutService
      // (verified second session, stricter sshd -T checks) — module 20 no
      // longer carries an inline disable path, so no flag is emitted.
      'ENABLE_HARDENING': options.enableHardening ? 'true' : 'false',
      'SSH_PUBKEY': sshPublicKey ?? '',
      'USER_AUTHORIZED_KEYS_B64': userKeysB64,
      'INTERFACE_NAME': options.interfaceName,
      'WG_PORT': '${options.wgPort}',
      'SSH_PORT': '$sshPort',
      'VPN_SUBNET': options.vpnSubnet,
      'MTU': '${options.mtu}',
      'DNS': options.dns,
      'PUBLIC_ENDPOINT': options.publicEndpoint ?? '',
      'FAV_CONFIG_VERSION': '2',
      'FAV_INSTALLATION_ID': installationId,
      'FAV_OPERATION_ID': operationId,
      'VPN_IPV6_ULA_SUBNET': ipv6UlaSubnet,
      'VPN_IPV6_ROUTED_SUBNET': routed,
      'IPV6_PROBE_TARGET': options.ipv6ProbeTarget ?? '',
    };
    final buffer = StringBuffer();
    for (final entry in entries.entries) {
      buffer.writeln('${entry.key}="${_escape(entry.value)}"');
    }
    return buffer.toString();
  }

  bool _isSafeIdentity(String? value) =>
      value != null &&
      RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$').hasMatch(value);

  /// Escapes [value] for safe inclusion inside a double-quoted bash string.
  ///
  /// Control characters (newline, carriage return, ...) are rejected: they
  /// would let a value span lines and break the one-line-per-key invariant
  /// the orchestrator relies on when it sources the file. Backslash is escaped
  /// first so the backslashes added for the other metacharacters are not
  /// doubled.
  String _escape(String value) {
    if (RegExp(r'[\x00-\x1f\x7f]').hasMatch(value)) {
      // The value itself is never included in the error — it may be a secret.
      throw ArgumentError(
        'config.env values must not contain control characters',
      );
    }
    return value
        .replaceAll(r'\', r'\\')
        .replaceAll(r'$', r'\$')
        .replaceAll('"', r'\"')
        .replaceAll('`', r'\`');
  }
}
