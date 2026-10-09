import 'dart:async';

import 'package:fav/core/crypto/ed25519_keypair.dart';
import 'package:fav/core/errors/app_exception.dart';
import 'package:fav/features/install/application/ssh_auth_resolver.dart';
import 'package:fav/features/install/data/keys/ssh_key_repository.dart';
import 'package:fav/features/install/data/ssh/dart_ssh_client.dart';
import 'package:fav/features/install/domain/ssh_client.dart';
import 'package:fav/features/install/domain/ssh_shell_session.dart';
import 'package:fav/features/servers/data/hive_server_repository.dart';
import 'package:fav/features/shell/application/pending_shell_password.dart';
import 'package:fav/features/shell/presentation/shell_extra_keys_bar.dart';
import 'package:fav/features/shell/presentation/ssh_shell_screen.dart';
import 'package:fav/l10n/app_localizations.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

import '../../../support/fake_ssh_client.dart';
import '../../../support/server_fakes.dart';

/// Key repository never consulted for a password-auth server.
class _UnusedKeyRepository implements SshKeyRepository {
  @override
  Future<Ed25519KeyPair?> get(String serverId) =>
      throw UnimplementedError('key repo should not be used');

  @override
  Future<Ed25519KeyPair> getOrCreate({
    required String serverId,
    required String comment,
  }) => throw UnimplementedError('key repo should not be used');

  @override
  Future<void> delete(String serverId) async {}
}

/// [SshClient] whose [connect] never completes, so the screen stays in the
/// connecting state.
class _HangingSshClient implements SshClient {
  @override
  Future<void> connect(SshConnectionParams params) => Completer<void>().future;

  @override
  Future<SshCommandResult> run(String command, {String? stdin}) async =>
      const SshCommandResult(stdout: '', stderr: '', exitCode: 0);

  @override
  Future<void> uploadBytes({
    required String remotePath,
    required List<int> data,
  }) async {}

  @override
  Future<SshShellSession> startShell({int columns = 80, int rows = 24}) =>
      throw UnimplementedError();

  @override
  Future<void> close() async {}
}

void main() {
  Future<PendingShellPasswords> pumpScreen(
    WidgetTester tester,
    SshClient client,
  ) async {
    final servers = FakeServerRepository();
    await servers.save(testServer());
    // The password reaches the screen through the in-memory holder, never
    // through a route `extra` (go_router JSON-encodes extras into the
    // engine's route-information state — audit MEDIUM-2).
    final passwords = PendingShellPasswords()..put('srv-1', 'pw');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          serverRepositoryProvider.overrideWithValue(servers),
          sshAuthResolverProvider.overrideWithValue(
            SshAuthResolver(_UnusedKeyRepository()),
          ),
          sshClientFactoryProvider.overrideWithValue(() => client),
          pendingShellPasswordsProvider.overrideWithValue(passwords),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SshShellScreen(serverId: 'srv-1'),
        ),
      ),
    );
    return passwords;
  }

  testWidgets('shows a spinner while connecting', (tester) async {
    await pumpScreen(tester, _HangingSshClient());
    await tester.pump(); // run post-frame start(); connect never completes
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('renders the terminal once connected', (tester) async {
    final passwords = await pumpScreen(tester, FakeSshClient(const {}));
    await tester.pump(); // run post-frame start()
    await tester.pump(const Duration(milliseconds: 50)); // flush async connect
    expect(find.byType(TerminalView), findsOneWidget);
    // The screen consumed the staged password: nothing lingers.
    expect(passwords.take('srv-1'), isNull);
  });

  testWidgets('desktop terminal accepts hardware keyboard input', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      final client = FakeSshClient(const {});
      await pumpScreen(tester, client);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final view = tester.widget<TerminalView>(find.byType(TerminalView));
      expect(view.hardwareKeyboardOnly, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);

      final sent = client.shellSession.writes.map(String.fromCharCodes).join();
      expect(sent, contains('a'));
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('shows an error with a retry action on failure', (tester) async {
    await pumpScreen(
      tester,
      FakeSshClient(
        const {},
        connectError: const AppException(ErrorCode.connHostUnreachable),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l10n.shellError), findsOneWidget);
    expect(find.text(l10n.shellRetry), findsOneWidget);
  });

  testWidgets('hides the extra keys bar while connecting', (tester) async {
    await pumpScreen(tester, _HangingSshClient());
    await tester.pump();
    expect(find.byType(ShellExtraKeysBar), findsNothing);
  });

  testWidgets('shows the extra keys bar once connected', (tester) async {
    await pumpScreen(tester, FakeSshClient(const {}));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(ShellExtraKeysBar), findsOneWidget);
  });

  testWidgets('extra bar keys reach the session as escape sequences', (
    tester,
  ) async {
    final client = FakeSshClient(const {});
    await pumpScreen(tester, client);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    await tester.tap(find.text(l10n.shellKeyEsc));
    await tester.tap(find.byIcon(Icons.keyboard_arrow_up));
    await tester.tap(find.text('/'));

    final sent = client.shellSession.writes.map(String.fromCharCodes).toList();
    expect(sent, ['\x1b', '\x1b[A', '/']);
  });

  testWidgets('sticky CTRL turns the next typed character into a control '
      'code, then disarms', (tester) async {
    final client = FakeSshClient(const {});
    await pumpScreen(tester, client);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    await tester.tap(find.text(l10n.shellKeyCtrl));
    await tester.pump();
    tester.testTextInput.enterText('c');
    await tester.pump();
    tester.testTextInput.enterText('d');
    await tester.pump();

    final sent = client.shellSession.writes.map(String.fromCharCodes).toList();
    expect(sent, ['\x03', 'd']);
  });

  testWidgets('the paste key sends the clipboard text to the session', (
    tester,
  ) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => call.method == 'Clipboard.getData'
          ? <String, dynamic>{'text': 'hello-clip'}
          : null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final client = FakeSshClient(const {});
    await pumpScreen(tester, client);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.byIcon(Icons.content_paste));
    await tester.pump();

    final sent = client.shellSession.writes.map(String.fromCharCodes).join();
    expect(sent, contains('hello-clip'));
  });

  testWidgets('the copy key without a selection touches nothing', (
    tester,
  ) async {
    var clipboardWrites = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') clipboardWrites++;
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final client = FakeSshClient(const {});
    await pumpScreen(tester, client);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.byIcon(Icons.copy));
    await tester.pump();

    expect(clipboardWrites, 0, reason: 'no selection → clipboard untouched');
    expect(client.shellSession.writes, isEmpty);
  });

  testWidgets('forwards remote output to the terminal', (tester) async {
    final client = FakeSshClient(const {});
    await pumpScreen(tester, client);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    client.shellSession.emit('hello-from-server\r\n'.codeUnits);
    await tester.pump(const Duration(milliseconds: 50));
    expect(client.shellSession.closed, isFalse);
  });
}
