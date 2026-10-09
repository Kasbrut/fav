import 'dart:convert';

import 'package:fav/features/install/data/provisioner/config_env_writer.dart';
import 'package:fav/features/install/domain/advanced_options.dart';
import 'package:fav/features/install/domain/new_user_spec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const writer = ConfigEnvWriter();

  String render({
    AdvancedOptions options = const AdvancedOptions(),
    String installationId = 'install-1',
    String operationId = 'operation-1',
    String ipv6UlaSubnet = 'fd12:3456:789a::/64',
    NewUserSpec? newUser,
    String? sshPublicKey,
    String? loginUser,
    int sshPort = 22,
  }) => writer.render(
    options: options,
    installationId: installationId,
    operationId: operationId,
    ipv6UlaSubnet: ipv6UlaSubnet,
    newUser: newUser,
    sshPublicKey: sshPublicKey,
    loginUser: loginUser,
    sshPort: sshPort,
  );

  test('rejects subnets the fixed-size peer allocator cannot represent', () {
    expect(
      () => render(options: const AdvancedOptions(vpnSubnet: '10.0.0.0/16')),
      throwsArgumentError,
    );
  });
  test('passes the SSH port to fail2ban configuration', () {
    final text = render(sshPort: 2222);
    expect(text, contains('SSH_PORT="2222"'));
  });

  Map<String, String> parse(String content) {
    final map = <String, String>{};
    for (final line in content.split('\n')) {
      if (line.isEmpty) {
        continue;
      }
      final eq = line.indexOf('=');
      map[line.substring(0, eq)] = line.substring(eq + 1);
    }
    return map;
  }

  test('renders every documented config.env key', () {
    final keys = parse(render()).keys;
    expect(keys.toSet(), {
      'CREATE_USER',
      'NEW_USERNAME',
      'NEW_PASSWORD',
      'ENABLE_HARDENING',
      'SSH_PUBKEY',
      'INTERFACE_NAME',
      'WG_PORT',
      'SSH_PORT',
      'VPN_SUBNET',
      'MTU',
      'DNS',
      'PUBLIC_ENDPOINT',
      'USER_AUTHORIZED_KEYS_B64',
      'FAV_CONFIG_VERSION',
      'FAV_INSTALLATION_ID',
      'FAV_OPERATION_ID',
      'VPN_IPV6_ULA_SUBNET',
      'VPN_IPV6_ROUTED_SUBNET',
      'IPV6_PROBE_TARGET',
    });
  });

  test('quotes every v2 transport field and preserves optional empties', () {
    final map = parse(
      render(
        options: const AdvancedOptions(
          delegatedIpv6Prefix: '2001:4860:1234:1::/64',
          ipv6ProbeTarget: '2001:4860:4860::8888',
        ),
      ),
    );
    expect(map['FAV_CONFIG_VERSION'], '"2"');
    expect(map['FAV_INSTALLATION_ID'], '"install-1"');
    expect(map['FAV_OPERATION_ID'], '"operation-1"');
    expect(map['VPN_IPV6_ULA_SUBNET'], '"fd12:3456:789a::/64"');
    expect(map['VPN_IPV6_ROUTED_SUBNET'], '"2001:4860:1234:1::/64"');
    expect(map['IPV6_PROBE_TARGET'], '"2001:4860:4860::8888"');
  });

  test('rejects incomplete or unsafe v2 transport identities', () {
    expect(
      () => render(
        operationId: '',
        ipv6UlaSubnet: '',
      ),
      throwsArgumentError,
    );
    expect(
      () => render(
        installationId: r'bad$(id)',
      ),
      throwsArgumentError,
    );
  });

  test('NEW_USERNAME falls back to the login user when no user is created', () {
    final map = parse(
      render(loginUser: 'operator'),
    );
    expect(map['CREATE_USER'], '"false"');
    // So 25_deploy_app_key / 26_deploy_user_keys target the login user, not
    // root, when installing as an existing non-root sudoer.
    expect(map['NEW_USERNAME'], '"operator"');
  });

  test('NEW_USERNAME prefers the created user over the login user', () {
    final map = parse(
      render(
        newUser: const NewUserSpec(username: 'lollo', password: 'pw'),
        loginUser: 'operator',
      ),
    );
    expect(map['CREATE_USER'], '"true"');
    expect(map['NEW_USERNAME'], '"lollo"');
  });

  test('SSH_PUBKEY is empty by default', () {
    final map = parse(render());
    expect(map['SSH_PUBKEY'], '""');
  });

  test('SSH_PUBKEY carries the provided authorized_keys line', () {
    const pubkey = 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA fav@id';
    final map = parse(
      render(
        options: const AdvancedOptions(enableHardening: true),
        sshPublicKey: pubkey,
      ),
    );
    expect(map['ENABLE_HARDENING'], '"true"');
    expect(map['SSH_PUBKEY'], '"$pubkey"');
  });

  test('USER_AUTHORIZED_KEYS_B64 is empty by default', () {
    final map = parse(render());
    expect(map['USER_AUTHORIZED_KEYS_B64'], '""');
  });

  test('USER_AUTHORIZED_KEYS_B64 base64-encodes the newline-joined keys', () {
    const k1 = 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA user@laptop';
    const k2 = 'ssh-rsa AAAAB3NzaC1yc2E= desktop';
    final map = parse(
      render(
        options: const AdvancedOptions(userAuthorizedKeys: [k1, k2]),
      ),
    );
    final value = map['USER_AUTHORIZED_KEYS_B64']!;
    // Strip the surrounding quotes added by the renderer.
    final b64 = value.substring(1, value.length - 1);
    expect(utf8.decode(base64.decode(b64)), '$k1\n$k2');
  });

  test('CREATE_USER is false when no user is requested', () {
    final map = parse(render());
    expect(map['CREATE_USER'], '"false"');
    expect(map['NEW_PASSWORD'], '""');
  });

  test('CREATE_USER is true when a new user is requested', () {
    final map = parse(
      render(
        newUser: const NewUserSpec(username: 'deploy', password: 'pw'),
      ),
    );
    expect(map['CREATE_USER'], '"true"');
    expect(map['NEW_USERNAME'], '"deploy"');
  });

  test('DISABLE_ROOT_SSH is gone (module 20 no longer reads it)', () {
    final withUser = parse(
      render(
        newUser: const NewUserSpec(username: 'deploy', password: 'pw'),
      ),
    );
    final withoutUser = parse(render());
    expect(withUser.containsKey('DISABLE_ROOT_SSH'), isFalse);
    expect(withoutUser.containsKey('DISABLE_ROOT_SSH'), isFalse);
  });

  test('escapes shell metacharacters so a value cannot break out', () {
    final map = parse(
      render(
        newUser: const NewUserSpec(username: 'deploy', password: r'a"b$c`d\e'),
      ),
    );
    expect(map['NEW_PASSWORD'], r'"a\"b\$c\`d\\e"');
  });

  test('rejects a value containing a control character', () {
    expect(
      () => render(
        newUser: const NewUserSpec(username: 'deploy', password: 'a\nb'),
      ),
      throwsArgumentError,
    );
  });
}
