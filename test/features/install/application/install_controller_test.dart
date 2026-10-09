import 'dart:convert';
import 'dart:typed_data';

import 'package:fav/core/errors/app_exception.dart';
import 'package:fav/core/utils/app_logger.dart';
import 'package:fav/features/install/application/install_controller.dart';
import 'package:fav/features/install/application/run_recovery_provider.dart';
import 'package:fav/features/install/data/hive_run_repository.dart';
import 'package:fav/features/install/data/keys/ssh_key_repository.dart';
import 'package:fav/features/install/data/scripts/hive_user_script_repository.dart';
import 'package:fav/features/install/data/scripts/script_integrity.dart';
import 'package:fav/features/install/data/ssh/dart_ssh_client.dart';
import 'package:fav/features/install/domain/advanced_options.dart';
import 'package:fav/features/install/domain/install_run.dart';
import 'package:fav/features/install/domain/management_identity.dart';
import 'package:fav/features/install/domain/run_paths.dart';
import 'package:fav/features/install/domain/script_source.dart';
import 'package:fav/features/install/domain/ssh_client.dart';
import 'package:fav/features/install/domain/user_script.dart';
import 'package:fav/features/install/domain/user_script_repository.dart';
import 'package:fav/features/peers/application/peer_secret_provider.dart';
import 'package:fav/features/peers/data/hive_peer_repository.dart';
import 'package:fav/features/peers/data/secure_peer_secret_repository.dart';
import 'package:fav/features/peers/domain/peer.dart';
import 'package:fav/features/peers/domain/peer_repository.dart';
import 'package:fav/features/peers/domain/peer_secret_repository.dart';
import 'package:fav/features/servers/data/hive_server_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';

import '../../../support/capturing_logger.dart';
import '../../../support/in_memory_run_repository.dart';
import '../../../support/in_memory_secure_store.dart';
import '../../../support/in_memory_user_script_repository.dart';
import '../../../support/recording_ssh_client.dart';
import '../../../support/server_fakes.dart';

class _InMemoryPeerRepository implements PeerRepository {
  final Map<String, Peer> _peers = {};

  @override
  Future<List<Peer>> getAll() async => _peers.values.toList();

  @override
  Future<Peer?> getById(String id) async => _peers[id];

  @override
  Future<List<Peer>> getByServerId(String serverId) async =>
      _peers.values.where((peer) => peer.serverId == serverId).toList();

  @override
  Future<void> save(Peer peer) async => _peers[peer.id] = peer;

  @override
  Future<void> delete(String id) async => _peers.remove(id);
}

class _InMemoryPeerSecrets implements PeerSecretRepository {
  final Map<String, String> _entries = {};

  @override
  Future<void> save({required String peerId, required String rawConf}) async {
    _entries[peerId] = rawConf;
  }

  @override
  Future<String?> read(String peerId) async => _entries[peerId];

  @override
  Future<void> delete(String peerId) async => _entries.remove(peerId);
}

void main() {
  ScriptBundle fakeBundle() => ScriptBundle(
    assets: [
      ScriptAsset(
        relativePath: 'disable_root_ssh.sh',
        bytes: Uint8List.fromList('# script'.codeUnits),
      ),
      ...fakeTeardownBundle().assets,
    ],
    bundleHash: 'test-hash',
  );

  ProviderContainer makeContainer({
    required RecordingSshClient client,
    Exception? integrityError,
    UserScriptRepository? userScripts,
    Logger? logger,
    InMemoryRunRepository? runRepository,
    List<Override> extraOverrides = const [],
  }) {
    final container = ProviderContainer(
      // Match production (main.dart): no Riverpod 3 auto-retry, so a failing
      // provider surfaces its error as a terminal state instead of looping.
      retry: (_, _) => null,
      overrides: [
        sshClientFactoryProvider.overrideWithValue(() => client),
        bootIntegrityProvider.overrideWith((ref) {
          if (integrityError != null) {
            throw integrityError;
          }
          return fakeBundle();
        }),
        userScriptRepositoryProvider.overrideWithValue(
          userScripts ?? InMemoryUserScriptRepository(),
        ),
        // M15-T1: the controller now generates the app SSH key on every
        // install, not only on hardening. Provide an in-memory store so the
        // unit test does not depend on flutter_secure_storage bindings.
        sshKeyRepositoryProvider.overrideWithValue(
          SecureSshKeyRepository(InMemorySecureStore()),
        ),
        // The polling controller persists run snapshots on every poll.
        runRepositoryProvider.overrideWithValue(
          runRepository ?? InMemoryRunRepository(),
        ),
        if (logger != null) loggerProvider.overrideWithValue(logger),
        ...extraOverrides,
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<void> startInstall(
    ProviderContainer container, {
    AdvancedOptions options = const AdvancedOptions(),
  }) {
    return container
        .read(installControllerProvider.notifier)
        .start(
          server: testServer(),
          options: options,
          sshPassword: 'pw',
        );
  }

  test('fails when the bundled script integrity check fails', () async {
    final container = makeContainer(
      client: RecordingSshClient(),
      integrityError: const AppException(ErrorCode.scriptInvalid),
    );
    await startInstall(container);
    final state = container.read(installControllerProvider);
    expect(state, isA<InstallFailure>());
    expect((state as InstallFailure).error.code, ErrorCode.scriptInvalid);
  });

  test('logs every state transition with the failure code', () async {
    final output = CapturingLogOutput();
    final container = makeContainer(
      client: RecordingSshClient(
        onConnect: () =>
            throw const AppException(ErrorCode.connHostUnreachable),
      ),
      logger: capturingLogger(output),
    );
    await startInstall(container);

    expect(
      output.lines,
      contains(matches(RegExp('Install.*InstallPreparing'))),
      reason: 'intermediate transitions must be logged',
    );
    expect(
      output.lines,
      contains(
        matches(RegExp('Install.*InstallFailure.*connHostUnreachable')),
      ),
      reason: 'the failure transition must carry the error code',
    );
  });

  test('sanitizes the failure detail before logging it', () async {
    final output = CapturingLogOutput();
    final container = makeContainer(
      client: RecordingSshClient(
        onConnect: () => throw const AppException(
          ErrorCode.connHostUnreachable,
          detail: 'boom\nforged line password=hunter2',
        ),
      ),
      logger: capturingLogger(output),
    );
    await startInstall(container);

    final line = output.lines.firstWhere(
      (l) => l.contains('InstallFailure'),
    );
    expect(line, contains('boom'), reason: 'the detail must still be logged');
    expect(line, isNot(contains('\n')), reason: 'newlines must be collapsed');
    expect(
      line,
      isNot(contains('hunter2')),
      reason: 'secret-looking values must be redacted',
    );
    expect(line, contains('connHostUnreachable'));
  });

  test('cleanupRun reports success only via the stdout marker', () async {
    // First connect (the install) fails so the controller lands in
    // InstallFailure with the run paths set; the cleanup reconnects fine.
    var connects = 0;
    final client = RecordingSshClient(
      onConnect: () {
        connects++;
        if (connects == 1) {
          throw const AppException(ErrorCode.connHostUnreachable);
        }
      },
      // exit -1 mimics the plain-exec no-exit-code quirk: only the marker
      // may be trusted.
      onRun: (command) => const SshCommandResult(
        stdout: 'WG-CLN-OK\n',
        stderr: '',
        exitCode: -1,
      ),
    );
    final container = makeContainer(client: client);
    await startInstall(container);

    final ok = await container
        .read(installControllerProvider.notifier)
        .cleanupRun();

    expect(ok, isTrue);
    expect(client.runCommands.single, contains('rm -rf'));
    expect(client.runCommands.single, contains('/var/log/wg-installer/'));
  });

  test('cleanupRun elevates with sudo for a non-root login', () async {
    var connects = 0;
    final client = RecordingSshClient(
      onConnect: () {
        connects++;
        if (connects == 1) {
          throw const AppException(ErrorCode.connHostUnreachable);
        }
      },
      onRun: (command) => const SshCommandResult(
        stdout: 'WG-CLN-OK\n',
        stderr: '',
        exitCode: -1,
      ),
    );
    final container = makeContainer(client: client);
    await container
        .read(installControllerProvider.notifier)
        .start(
          server: testServer(username: 'wgadmin'),
          options: const AdvancedOptions(),
          sshPassword: 'pw',
        );

    final ok = await container
        .read(installControllerProvider.notifier)
        .cleanupRun();

    expect(ok, isTrue);
    expect(client.runCommands.single, contains("sudo -S -p ''"));
    expect(client.runStdins.single, 'pw\n');
  });

  test('cleanupRun reports failure when the marker is missing', () async {
    var connects = 0;
    final client = RecordingSshClient(
      onConnect: () {
        connects++;
        if (connects == 1) {
          throw const AppException(ErrorCode.connHostUnreachable);
        }
      },
      onRun: (command) =>
          const SshCommandResult(stdout: '', stderr: 'lost', exitCode: -1),
    );
    final container = makeContainer(client: client);
    await startInstall(container);

    final ok = await container
        .read(installControllerProvider.notifier)
        .cleanupRun();

    expect(ok, isFalse);
  });

  // The remote state file the poller reads on a terminally failed run.
  const failedPoll =
      '{"run_id":"run-1","started_at":"2026-08-19T10:00:00Z",'
      '"steps":{"probe":{"status":"done"}},"warnings":[],"error":null}\n'
      '---WG-EXIT---\n1';

  /// Canned server for a full install whose run exits with code 1.
  SshCommandResult failedInstallServer(String c) {
    if (c.contains('teardown_wireguard.sh')) {
      return const SshCommandResult(
        stdout: 'WG-TRD-OK\n',
        stderr: '',
        exitCode: 0,
      );
    }
    if (c.contains('/tmp/wg-trd-') && c.contains('mkdir')) {
      return const SshCommandResult(
        stdout: 'WG-TRD-STAGED\n',
        stderr: '',
        exitCode: 0,
      );
    }
    if (c.contains('ls /etc/wireguard')) {
      return const SshCommandResult(stdout: '', stderr: '', exitCode: 1);
    }
    if (c.contains("stat -c '%a'")) {
      return const SshCommandResult(stdout: '600', stderr: '', exitCode: 0);
    }
    if (c.contains('/var/lib/wg-installer/') && c.contains('cat')) {
      return const SshCommandResult(
        stdout: failedPoll,
        stderr: '',
        exitCode: 0,
      );
    }
    return const SshCommandResult(stdout: '', stderr: '', exitCode: 0);
  }

  test('reset fires the cleanup only after a terminally failed run', () async {
    final client = RecordingSshClient(onRun: failedInstallServer);
    final container = makeContainer(client: client);
    await startInstall(container);
    final state = container.read(installControllerProvider);
    expect(state, isA<InstallFailure>());
    expect((state as InstallFailure).run?.status, RunStatus.failed);
    expect(
      client.runCommands.where((c) => c.contains('teardown_wireguard.sh')),
      hasLength(1),
      reason: 'a terminal failure must roll back partial server changes',
    );
    expect(
      client.runCommands.where(
        (c) => c.contains('rm -rf') && c.contains('/var/log/wg-installer'),
      ),
      isEmpty,
      reason: 'rollback keeps the failed run log available for diagnostics',
    );

    container.read(installControllerProvider.notifier).reset();
    // Let the fire-and-forget cleanup settle.
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(
      client.runCommands.where((c) => c.contains('WG-CLN-OK')),
      hasLength(1),
      reason: 'leaving the failure screen must trigger the cleanup',
    );
    expect(container.read(installControllerProvider), isA<InstallIdle>());
  });

  test('reset does not clean up while the installer may still run', () async {
    // A launch failure leaves run.status != failed (no exit file was ever
    // observed): the detached installer could still be alive, so wiping the
    // run dir would kill it mid-flight (security review H1).
    final client = RecordingSshClient(
      onRun: (command) =>
          const SshCommandResult(stdout: '', stderr: 'boom', exitCode: 1),
    );
    final runs = InMemoryRunRepository();
    final container = makeContainer(client: client, runRepository: runs);
    await startInstall(container);
    expect(container.read(installControllerProvider), isA<InstallFailure>());
    expect(runs.runs, isNotEmpty);
    expect(runs.runs.last.installationId, isNotEmpty);
    expect(runs.runs.last.operationId, isNotEmpty);
    expect(runs.runs.last.ipv6UlaSubnet, startsWith('fd'));

    container.read(installControllerProvider.notifier).reset();
    await Future<void>.delayed(Duration.zero);

    expect(
      client.runCommands.where((c) => c.contains('WG-CLN-OK')),
      isEmpty,
      reason: 'no exit file observed → the run may still be alive',
    );
  });

  test('reset after a pre-launch failure does not attempt a cleanup', () async {
    final client = RecordingSshClient();
    final container = makeContainer(
      client: client,
      integrityError: const AppException(ErrorCode.scriptInvalid),
    );
    await startInstall(container);
    expect(container.read(installControllerProvider), isA<InstallFailure>());

    container.read(installControllerProvider.notifier).reset();
    await Future<void>.delayed(Duration.zero);

    expect(client.connectCount, 0);
    expect(client.runCommands, isEmpty);
  });

  test('fails when the SSH connection cannot be established', () async {
    final container = makeContainer(
      client: RecordingSshClient(
        onConnect: () =>
            throw const AppException(ErrorCode.connHostUnreachable),
      ),
    );
    await startInstall(container);
    expect(container.read(installControllerProvider), isA<InstallFailure>());
  });

  test('maps a transport failure during the pre-install probe', () async {
    final container = makeContainer(
      client: RecordingSshClient(
        onRun: (_) => throw StateError('connection reset'),
      ),
    );

    await startInstall(container);

    final state = container.read(installControllerProvider);
    expect(state, isA<InstallFailure>());
    expect(
      (state as InstallFailure).error.code,
      ErrorCode.connHostUnreachable,
    );
    expect(state.run, isNull);
  });

  test('maps an interrupted upload to a connection failure', () async {
    final container = makeContainer(
      client: RecordingSshClient(
        onUpload: (_) => throw StateError('connection reset'),
      ),
    );

    await startInstall(container);

    final state = container.read(installControllerProvider);
    expect(state, isA<InstallFailure>());
    expect(
      (state as InstallFailure).error.code,
      ErrorCode.connHostUnreachable,
    );
    expect(state.run?.status, RunStatus.orphaned);
  });

  test('keeps an uncertain detached launch recoverable', () async {
    final container = makeContainer(
      client: RecordingSshClient(
        onRun: (command) {
          if (command.contains("stat -c '%a'")) {
            return const SshCommandResult(
              stdout: '600\n',
              stderr: '',
              exitCode: 0,
            );
          }
          if (command.contains('nohup setsid')) {
            throw StateError('connection reset');
          }
          return const SshCommandResult(stdout: '', stderr: '', exitCode: 0);
        },
      ),
    );

    await startInstall(container);

    final state = container.read(installControllerProvider) as InstallFailure;
    expect(state.error.code, ErrorCode.connHostUnreachable);
    expect(state.run?.status, RunStatus.running);
    expect(
      await container.read(runRepositoryProvider).getIncomplete(),
      hasLength(1),
    );
  });

  test('a connect failure carries no run (F11)', () async {
    // Wrong login password / unreachable host: nothing was ever created on
    // the server, so the failure must not reference a run — the failure
    // screen keys "View full log" on it, and there is no remote log.
    final container = makeContainer(
      client: RecordingSshClient(
        onConnect: () =>
            throw const AppException(ErrorCode.authInvalidCredentials),
      ),
    );
    await startInstall(container);
    final state = container.read(installControllerProvider);
    expect(state, isA<InstallFailure>());
    expect((state as InstallFailure).run, isNull);
    expect(state.error.code, ErrorCode.authInvalidCredentials);
    expect(
      container.read(installControllerProvider.notifier).retryServer,
      testServer(),
    );
  });

  test('asks for confirmation when WireGuard is already installed', () async {
    final container = makeContainer(
      client: RecordingSshClient(
        onRun: (command) => const SshCommandResult(
          stdout: 'WG-PRESENT\n',
          stderr: '',
          exitCode: 0,
        ),
      ),
    );
    await startInstall(container);
    expect(
      container.read(installControllerProvider),
      isA<InstallNeedsConfirmation>(),
    );
  });

  group('resolveManagedUsername (C1 — post-install login user)', () {
    test(
      'uses the created management user even when root SSH stays enabled',
      () {
        // Root login always creates a management user and the app key is
        // deployed only to that user (module 25 / NEW_USERNAME). With hardening
        // OFF (the default) root SSH stays enabled, but the app must still
        // connect as the key-bearing management user — never as root, whose
        // authorized_keys never received the key — or it locks itself out.
        const identity = ManagementIdentity(
          username: 'wgadmin',
          password: 'pw',
          createdByUs: true,
        );
        expect(
          InstallController.resolveManagedUsername(
            identity: identity,
            loginUsername: 'root',
          ),
          'wgadmin',
        );
      },
    );

    test('uses the login user for a non-root sudoer install', () {
      const identity = ManagementIdentity(
        username: 'deploy',
        password: 'pw',
        createdByUs: false,
      );
      expect(
        InstallController.resolveManagedUsername(
          identity: identity,
          loginUsername: 'deploy',
        ),
        'deploy',
      );
    });
  });

  test('attachRecovered finalizes with the persisted options (M3)', () async {
    const paths = RunPaths('recovered-run');
    final client = RecordingSshClient(
      onRun: (command) {
        // First poll observes the exit file immediately; every other command
        // (metadata reads, cleanup) returns empty output.
        if (command.contains(paths.statePath)) {
          return const SshCommandResult(
            stdout: '---WG-EXIT---\n0',
            stderr: '',
            exitCode: 0,
          );
        }
        return const SshCommandResult(stdout: '', stderr: '', exitCode: 0);
      },
    );
    final servers = FakeServerRepository();
    await servers.save(testServer());
    final container = makeContainer(
      client: client,
      extraOverrides: [serverRepositoryProvider.overrideWithValue(servers)],
    );

    final run = InstallRun(
      runId: 'recovered-run',
      serverId: 'srv-1',
      status: RunStatus.running,
      steps: const [],
      scriptWasModified: false,
      startedAt: DateTime(2026, 8, 19),
      options: const AdvancedOptions(
        wgPort: 51999,
        vpnSubnet: '10.66.0.0/24',
        interfaceName: 'wg7',
        enableMonitoring: false,
      ),
    );
    await container
        .read(installControllerProvider.notifier)
        .attachRecovered(
          client: client,
          run: run,
          paths: paths,
          server: testServer(),
          sshPassword: 'pw',
        );

    expect(container.read(installControllerProvider), isA<InstallSuccess>());
    // The metadata read targeted the run's actual interface, not the default.
    expect(
      client.runCommands.any((c) => c.contains('wg7_server_public.key')),
      isTrue,
    );
    final saved = await servers.getById('srv-1');
    expect(saved?.installation?.interfaceName, 'wg7');
    expect(saved?.installation?.listenPort, 51999);
    expect(saved?.installation?.vpnSubnet, '10.66.0.0/24');
  });

  test(
    'recovered v2 run fails closed when network result is missing',
    () async {
      const paths = RunPaths('operation-1');
      final client = RecordingSshClient(
        onRun: (command) => command.contains(paths.statePath)
            ? const SshCommandResult(
                stdout: '---WG-EXIT---\n0',
                stderr: '',
                exitCode: 0,
              )
            : const SshCommandResult(stdout: '', stderr: '', exitCode: 0),
      );
      final container = makeContainer(client: client);
      await container
          .read(installControllerProvider.notifier)
          .attachRecovered(
            client: client,
            run: InstallRun(
              runId: 'operation-1',
              serverId: 'srv-1',
              status: RunStatus.running,
              steps: const [],
              scriptWasModified: false,
              startedAt: DateTime(2026, 9, 17),
              options: const AdvancedOptions(enableMonitoring: false),
              installationId: 'installation-1',
              operationId: 'operation-1',
              ipv6UlaSubnet: 'fd12:3456:789a::/64',
            ),
            paths: paths,
            server: testServer(),
            sshPassword: 'pw',
          );
      final state = container.read(installControllerProvider);
      expect(state, isA<InstallFailure>());
      expect(
        (state as InstallFailure).error.detail,
        'missing v2 network result',
      );
    },
  );

  test('recovered v2 run persists only a validated server result', () async {
    const paths = RunPaths('operation-1');
    const profile = '''
[Interface]
PrivateKey = AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=
Address = 10.13.13.2/32, fd12:3456:789a::2/128
DNS = 1.1.1.1
MTU = 1420

[Peer]
PublicKey = AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=
PresharedKey = AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=
Endpoint = 192.0.2.1:51820
AllowedIPs = 0.0.0.0/0, ::/0
''';
    final result = jsonEncode({
      'schemaVersion': 2,
      'installationId': 'installation-1',
      'operationId': 'operation-1',
      'revision': 1,
      'network': {
        'ipv4Subnet': '10.13.13.0/24',
        'ipv6Mode': 'blocked',
        'ipv6Subnet': 'fd12:3456:789a::/64',
        'fallbackIpv6Subnet': 'fd12:3456:789a::/64',
        'serverIpv6Address': 'fd12:3456:789a::1/64',
      },
      'capability': {
        'status': 'unknown',
        'reason': 'probe_target_missing',
        'checkedAt': '2026-09-17T10:00:00Z',
      },
    });
    final client = RecordingSshClient(
      onRun: (command) {
        if (command.contains(paths.statePath)) {
          return const SshCommandResult(
            stdout: '---WG-EXIT---\n0',
            stderr: '',
            exitCode: 0,
          );
        }
        if (command.contains(paths.networkResultPath)) {
          return SshCommandResult(stdout: result, stderr: '', exitCode: 0);
        }
        if (command.contains('wg0_server_public.key')) {
          return const SshCommandResult(
            stdout: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=\n',
            stderr: '',
            exitCode: 0,
          );
        }
        if (command.contains(paths.clientConfigPath)) {
          return const SshCommandResult(
            stdout: profile,
            stderr: '',
            exitCode: 0,
          );
        }
        return const SshCommandResult(stdout: '', stderr: '', exitCode: 0);
      },
    );
    final servers = FakeServerRepository();
    final peers = _InMemoryPeerRepository();
    final secrets = _InMemoryPeerSecrets();
    await servers.save(testServer());
    final container = makeContainer(
      client: client,
      extraOverrides: [
        serverRepositoryProvider.overrideWithValue(servers),
        peerRepositoryProvider.overrideWithValue(peers),
        peerSecretRepositoryProvider.overrideWithValue(secrets),
      ],
    );
    await container
        .read(installControllerProvider.notifier)
        .attachRecovered(
          client: client,
          run: InstallRun(
            runId: 'operation-1',
            serverId: 'srv-1',
            status: RunStatus.running,
            steps: const [],
            scriptWasModified: false,
            startedAt: DateTime(2026, 9, 17),
            options: const AdvancedOptions(enableMonitoring: false),
            installationId: 'installation-1',
            operationId: 'operation-1',
            ipv6UlaSubnet: 'fd12:3456:789a::/64',
          ),
          paths: paths,
          server: testServer(),
          sshPassword: 'pw',
        );
    expect(container.read(installControllerProvider), isA<InstallSuccess>());
    expect(
      (await servers.getById('srv-1'))?.installation?.network?.installationId,
      'installation-1',
    );
    final savedPeers = await peers.getByServerId('srv-1');
    expect(savedPeers, hasLength(1));
    expect(savedPeers.single.ipv4Address, '10.13.13.2/32');
    expect(savedPeers.single.ipv6Address, 'fd12:3456:789a::2/128');
    expect(await secrets.read(savedPeers.single.id), profile);

    // Repair the exact incomplete record produced by early v2 builds, but
    // only through the normal provider's full profile/network validation.
    await peers.save(savedPeers.single.copyWith(clearIpv6Address: true));
    final recovered = await container.read(
      peerProfileProvider(savedPeers.single.id).future,
    );
    expect(recovered?.peer.ipv6Address, 'fd12:3456:789a::2/128');
    expect(
      (await peers.getById(savedPeers.single.id))?.ipv6Address,
      'fd12:3456:789a::2/128',
    );
  });

  test(
    'recovery restores the management identity when the key exists',
    () async {
      // The run deployed the app key to the management user (module 25); the
      // seed is still in the secure store. Finalizing the recovery as
      // root+password left key-only monitoring permanently broken (device
      // test 2026-08-19): restore username + sshKeyId when — and only when —
      // the local key pair actually exists.
      const paths = RunPaths('recovered-run');
      final client = RecordingSshClient(
        onRun: (command) {
          if (command.contains(paths.statePath)) {
            return const SshCommandResult(
              stdout: '---WG-EXIT---\n0',
              stderr: '',
              exitCode: 0,
            );
          }
          return const SshCommandResult(stdout: '', stderr: '', exitCode: 0);
        },
      );
      final servers = FakeServerRepository();
      await servers.save(testServer());
      final container = makeContainer(
        client: client,
        extraOverrides: [serverRepositoryProvider.overrideWithValue(servers)],
      );
      // Seed the same key pair the original run generated and deployed.
      await container
          .read(sshKeyRepositoryProvider)
          .getOrCreate(serverId: 'srv-1', comment: 'fav@srv-1');

      await container
          .read(installControllerProvider.notifier)
          .attachRecovered(
            client: client,
            run: InstallRun(
              runId: 'recovered-run',
              serverId: 'srv-1',
              status: RunStatus.running,
              steps: const [],
              scriptWasModified: false,
              startedAt: DateTime(2026, 8, 19),
              options: const AdvancedOptions(enableMonitoring: false),
              managementUsername: 'favops',
            ),
            paths: paths,
            server: testServer(),
            sshPassword: 'pw',
          );

      expect(container.read(installControllerProvider), isA<InstallSuccess>());
      final saved = await servers.getById('srv-1');
      expect(saved?.username, 'favops');
      expect(saved?.sshKeyId, 'srv-1');
    },
  );

  test(
    'no sshKeyId when the state reports the key was never deployed',
    () async {
      // A user-edited bundle can skip module 25 (deploy_app_key) and still
      // succeed. Registering sshKeyId without the key on the server leaves
      // every later operation key-only against a missing authorized_key —
      // the C1 failure class. Positive evidence of a skipped deploy must
      // block the claim; absent step data keeps the recovery behavior.
      const paths = RunPaths('recovered-run');
      final stateRaw = jsonEncode({
        'run_id': 'recovered-run',
        'started_at': '2026-08-20T10:00:00Z',
        'current_step': 'finalize',
        'current_step_started_at': '2026-08-20T10:05:00Z',
        'steps': {
          'deploy_app_key': {'status': 'skipped'},
        },
        'warnings': <String>[],
        'error': null,
      });
      final client = RecordingSshClient(
        onRun: (command) {
          if (command.contains(paths.statePath)) {
            return SshCommandResult(
              stdout: '$stateRaw\n---WG-EXIT---\n0',
              stderr: '',
              exitCode: 0,
            );
          }
          return const SshCommandResult(stdout: '', stderr: '', exitCode: 0);
        },
      );
      final servers = FakeServerRepository();
      await servers.save(testServer());
      final container = makeContainer(
        client: client,
        extraOverrides: [serverRepositoryProvider.overrideWithValue(servers)],
      );
      await container
          .read(sshKeyRepositoryProvider)
          .getOrCreate(serverId: 'srv-1', comment: 'fav@srv-1');

      await container
          .read(installControllerProvider.notifier)
          .attachRecovered(
            client: client,
            run: InstallRun(
              runId: 'recovered-run',
              serverId: 'srv-1',
              status: RunStatus.running,
              steps: const [],
              scriptWasModified: false,
              startedAt: DateTime(2026, 8, 20),
              options: const AdvancedOptions(enableMonitoring: false),
              managementUsername: 'favops',
            ),
            paths: paths,
            server: testServer(),
            sshPassword: 'pw',
          );

      expect(container.read(installControllerProvider), isA<InstallSuccess>());
      final saved = await servers.getById('srv-1');
      expect(saved?.sshKeyId, isNull);
    },
  );

  test(
    'negative deploy evidence clears a stale pre-existing sshKeyId',
    () async {
      // Re-install over a server that already carried a key claim: the run
      // reports deploy_app_key skipped AND the management account changed —
      // the old key belongs to the old account, so keeping the claim would
      // point key-only auth at an account with no authorized_keys
      // (verify-pass LOW-5).
      const paths = RunPaths('recovered-run');
      final stateRaw = jsonEncode({
        'run_id': 'recovered-run',
        'started_at': '2026-08-20T10:00:00Z',
        'current_step': 'finalize',
        'current_step_started_at': '2026-08-20T10:05:00Z',
        'steps': {
          'deploy_app_key': {'status': 'skipped'},
        },
        'warnings': <String>[],
        'error': null,
      });
      final client = RecordingSshClient(
        onRun: (command) {
          if (command.contains(paths.statePath)) {
            return SshCommandResult(
              stdout: '$stateRaw\n---WG-EXIT---\n0',
              stderr: '',
              exitCode: 0,
            );
          }
          return const SshCommandResult(stdout: '', stderr: '', exitCode: 0);
        },
      );
      final servers = FakeServerRepository();
      await servers.save(testServer().copyWith(sshKeyId: 'srv-1'));
      final container = makeContainer(
        client: client,
        extraOverrides: [serverRepositoryProvider.overrideWithValue(servers)],
      );
      await container
          .read(sshKeyRepositoryProvider)
          .getOrCreate(serverId: 'srv-1', comment: 'fav@srv-1');

      await container
          .read(installControllerProvider.notifier)
          .attachRecovered(
            client: client,
            run: InstallRun(
              runId: 'recovered-run',
              serverId: 'srv-1',
              status: RunStatus.running,
              steps: const [],
              scriptWasModified: false,
              startedAt: DateTime(2026, 8, 20),
              options: const AdvancedOptions(enableMonitoring: false),
              managementUsername: 'favops',
            ),
            paths: paths,
            server: testServer().copyWith(sshKeyId: 'srv-1'),
            sshPassword: 'pw',
          );

      expect(container.read(installControllerProvider), isA<InstallSuccess>());
      final saved = await servers.getById('srv-1');
      expect(saved?.sshKeyId, isNull);
    },
  );

  test('recovery keeps the login identity when the key is missing', () async {
    // Registering sshKeyId without the matching local key would make every
    // later operation authenticate key-only against nothing (C1 class).
    const paths = RunPaths('recovered-run');
    final client = RecordingSshClient(
      onRun: (command) {
        if (command.contains(paths.statePath)) {
          return const SshCommandResult(
            stdout: '---WG-EXIT---\n0',
            stderr: '',
            exitCode: 0,
          );
        }
        return const SshCommandResult(stdout: '', stderr: '', exitCode: 0);
      },
    );
    final servers = FakeServerRepository();
    await servers.save(testServer());
    final container = makeContainer(
      client: client,
      extraOverrides: [serverRepositoryProvider.overrideWithValue(servers)],
    );

    await container
        .read(installControllerProvider.notifier)
        .attachRecovered(
          client: client,
          run: InstallRun(
            runId: 'recovered-run',
            serverId: 'srv-1',
            status: RunStatus.running,
            steps: const [],
            scriptWasModified: false,
            startedAt: DateTime(2026, 8, 19),
            options: const AdvancedOptions(enableMonitoring: false),
            managementUsername: 'favops',
          ),
          paths: paths,
          server: testServer(),
          sshPassword: 'pw',
        );

    final saved = await servers.getById('srv-1');
    expect(saved?.username, 'root');
    expect(saved?.sshKeyId, isNull);
  });

  test('a finished recovered run drops off the incomplete list', () async {
    // The resume banner reads the cached incompleteRunsProvider: without an
    // invalidate at the terminal transition it kept offering to resume a run
    // that had already completed (device test 2026-08-19).
    const paths = RunPaths('recovered-run');
    final client = RecordingSshClient(
      onRun: (command) {
        if (command.contains(paths.statePath)) {
          return const SshCommandResult(
            stdout: '---WG-EXIT---\n0',
            stderr: '',
            exitCode: 0,
          );
        }
        return const SshCommandResult(stdout: '', stderr: '', exitCode: 0);
      },
    );
    final run = InstallRun(
      runId: 'recovered-run',
      serverId: 'srv-1',
      status: RunStatus.running,
      steps: const [],
      scriptWasModified: false,
      startedAt: DateTime(2026, 8, 19),
      options: const AdvancedOptions(enableMonitoring: false),
    );
    final runs = InMemoryRunRepository();
    await runs.save(run);
    final servers = FakeServerRepository();
    await servers.save(testServer());
    final container = makeContainer(
      client: client,
      runRepository: runs,
      extraOverrides: [serverRepositoryProvider.overrideWithValue(servers)],
    );
    // An active listener caches the provider, like the server list does.
    final subscription = container.listen(incompleteRunsProvider, (_, _) {});
    addTearDown(subscription.close);
    expect(await container.read(incompleteRunsProvider.future), hasLength(1));

    await container
        .read(installControllerProvider.notifier)
        .attachRecovered(
          client: client,
          run: run,
          paths: paths,
          server: testServer(),
          sshPassword: 'pw',
        );

    expect(container.read(installControllerProvider), isA<InstallSuccess>());
    expect(await container.read(incompleteRunsProvider.future), isEmpty);
  });

  test('start refuses while another flow is in flight (M2)', () async {
    final client = RecordingSshClient(
      onRun: (command) => const SshCommandResult(
        stdout: 'WG-PRESENT\n',
        stderr: '',
        exitCode: 0,
      ),
    );
    final container = makeContainer(client: client);
    await startInstall(container);
    expect(
      container.read(installControllerProvider),
      isA<InstallNeedsConfirmation>(),
    );
    expect(client.connectCount, 1);

    // A second start mid-flow must not clobber the live run's fields or
    // open a second connection.
    await startInstall(container);
    expect(client.connectCount, 1);
    expect(
      container.read(installControllerProvider),
      isA<InstallNeedsConfirmation>(),
    );
  });

  test(
    'attachRecovered refuses mid-flow and closes the offered client (M2)',
    () async {
      final client = RecordingSshClient(
        onRun: (command) => const SshCommandResult(
          stdout: 'WG-PRESENT\n',
          stderr: '',
          exitCode: 0,
        ),
      );
      final container = makeContainer(client: client);
      await startInstall(container);
      expect(
        container.read(installControllerProvider),
        isA<InstallNeedsConfirmation>(),
      );

      final recovered = RecordingSshClient();
      await container
          .read(installControllerProvider.notifier)
          .attachRecovered(
            client: recovered,
            run: InstallRun(
              runId: 'recovered-run',
              serverId: 'other-server',
              status: RunStatus.running,
              steps: const [],
              scriptWasModified: false,
              startedAt: DateTime(2026, 8, 19),
            ),
            paths: const RunPaths('recovered-run'),
            server: testServer(),
          );

      // Refused: the live flow is untouched and the recovered connection is
      // released instead of leaking.
      expect(
        container.read(installControllerProvider),
        isA<InstallNeedsConfirmation>(),
      );
      expect(recovered.closeCount, 1);
      expect(recovered.runCommands, isEmpty);
    },
  );

  test('cancel while connecting aborts before the probe (M4)', () async {
    late ProviderContainer container;
    final client = RecordingSshClient(
      onConnect: () {
        // The cancel lands while the controller is still connecting: nothing
        // may run on the server afterwards.
        container.read(installControllerProvider.notifier).cancel();
      },
    );
    container = makeContainer(client: client);
    await startInstall(container);

    final state = container.read(installControllerProvider);
    expect(state, isA<InstallFailure>());
    expect((state as InstallFailure).error.detail, contains('cancelled'));
    expect(client.runCommands, isEmpty);
    expect(client.uploads, isEmpty);
    expect(client.closeCount, 1);
  });

  test('cancel during the probe aborts before the launch (M4)', () async {
    late ProviderContainer container;
    final client = RecordingSshClient(
      onRun: (command) {
        container.read(installControllerProvider.notifier).cancel();
        return const SshCommandResult(stdout: '', stderr: '', exitCode: 0);
      },
    );
    container = makeContainer(client: client);
    await startInstall(container);

    final state = container.read(installControllerProvider);
    expect(state, isA<InstallFailure>());
    expect((state as InstallFailure).error.detail, contains('cancelled'));
    // Only the probe ran — no run-dir creation, no script upload, no launch.
    expect(client.runCommands, hasLength(1));
    expect(client.uploads, isEmpty);
    expect(client.closeCount, 1);
  });

  test('proceeds to confirmation even when a script override exists', () async {
    // Global overrides are resolved by EffectiveScriptResolver, not the
    // controller; a present override must not break the start flow. The
    // override-effect coverage lives in effective_script_resolver_test.
    final override = UserScript.fromContent(
      id: 'install_wireguard.sh',
      content: '#!/bin/bash\n# customized\n',
      createdAt: DateTime(2026, 5, 19),
    );
    final container = makeContainer(
      client: RecordingSshClient(
        onRun: (command) => const SshCommandResult(
          stdout: 'WG-PRESENT\n',
          stderr: '',
          exitCode: 0,
        ),
      ),
      userScripts: InMemoryUserScriptRepository([override]),
    );
    await startInstall(container);
    expect(
      container.read(installControllerProvider),
      isA<InstallNeedsConfirmation>(),
    );
  });
}
