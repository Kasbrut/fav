import 'dart:async';
import 'dart:convert';

import 'package:fav/core/errors/error_messages.dart';
import 'package:fav/core/theme/app_dimens.dart';
import 'package:fav/core/widgets/empty_state.dart';
import 'package:fav/core/widgets/primary_button.dart';
import 'package:fav/features/help/presentation/error_help_link.dart';
import 'package:fav/features/install/domain/ssh_shell_session.dart';
import 'package:fav/features/shell/application/pending_shell_password.dart';
import 'package:fav/features/shell/application/ssh_shell_controller.dart';
import 'package:fav/features/shell/presentation/shell_extra_keys_bar.dart';
import 'package:fav/features/shell/presentation/shell_key_input.dart';
import 'package:fav/l10n/app_localizations.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xterm/xterm.dart';

/// Full-screen interactive SSH terminal for a single server.
///
/// The connection is opened by [SshShellController] on first frame and torn
/// down when this screen leaves the tree (the provider auto-disposes). The
/// password (for password-auth servers) is taken from the in-memory
/// [PendingShellPasswords] holder — never from a route `extra`, which
/// go_router would JSON-encode into route-information state (audit
/// MEDIUM-2) — and lives only in memory for the session.
class SshShellScreen extends ConsumerStatefulWidget {
  /// Creates an [SshShellScreen] for [serverId].
  const SshShellScreen({required this.serverId, super.key});

  /// Identifier of the server to connect to.
  final String serverId;

  @override
  ConsumerState<SshShellScreen> createState() => _SshShellScreenState();
}

class _SshShellScreenState extends ConsumerState<SshShellScreen> {
  /// Shared between the [TerminalView] and the Scaffold background so the
  /// whole screen is one uniform colour — otherwise the terminal paints its
  /// own (lighter) background and any area it does not cover shows the page
  /// background through as a mismatched rectangle.
  static const TerminalTheme _terminalTheme = TerminalThemes.defaultTheme;

  late final Terminal _terminal = Terminal(maxLines: 10000);
  late final TerminalController _terminalController = TerminalController();
  StreamSubscription<String>? _outputSub;
  SshShellSession? _wiredSession;

  /// One-shot sticky modifiers armed from the extra-keys bar; they apply to
  /// the next key (bar or soft keyboard) and disarm on use.
  bool _ctrlArmed = false;
  bool _altArmed = false;

  bool get _usesHardwareKeyboardOnly =>
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.linux;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final password = ref
          .read(pendingShellPasswordsProvider)
          .take(widget.serverId);
      unawaited(
        ref
            .read(sshShellControllerProvider(widget.serverId).notifier)
            .start(password: password),
      );
    });
  }

  @override
  void dispose() {
    unawaited(_outputSub?.cancel());
    _terminalController.dispose();
    super.dispose();
  }

  /// Connects the xterm terminal to [session] once: remote output → terminal,
  /// keystrokes → remote stdin, terminal resize → remote PTY.
  void _wire(SshShellSession session) {
    if (identical(_wiredSession, session)) return;
    unawaited(_outputSub?.cancel());
    _wiredSession = session;
    _terminal.onOutput = (data) {
      final out = applyStickyModifiers(
        data,
        ctrl: _ctrlArmed,
        alt: _altArmed,
      );
      _disarmModifiers();
      session.write(Uint8List.fromList(utf8.encode(out)));
    };
    _terminal.onResize = (width, height, _, _) => ref
        .read(sshShellControllerProvider(widget.serverId).notifier)
        .resize(width, height);
    // A streaming decoder buffers multi-byte sequences split across packets.
    _outputSub = session.output
        .cast<List<int>>()
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen(_terminal.write);
  }

  void _unwire() {
    unawaited(_outputSub?.cancel());
    _outputSub = null;
    _wiredSession = null;
  }

  /// Sends a special key from the extra-keys bar, consuming any armed
  /// modifier. xterm encodes the modifiers into the escape sequence itself
  /// (e.g. CTRL+→ becomes a word-jump in most shells).
  void _onBarKey(TerminalKey key) {
    _terminal.keyInput(key, ctrl: _ctrlArmed, alt: _altArmed);
    _disarmModifiers();
  }

  /// Sends a character key from the extra-keys bar through the same
  /// [Terminal.onOutput] path the soft keyboard uses, so armed modifiers
  /// apply to it identically.
  void _onBarChar(String char) => _terminal.textInput(char);

  /// Copies the long-press selection to the clipboard and clears it.
  void _onCopy() {
    final selection = _terminalController.selection;
    if (selection == null) return;
    final text = _terminal.buffer.getText(selection);
    _terminalController.clearSelection();
    if (text.isEmpty) return;
    unawaited(Clipboard.setData(ClipboardData(text: text)));
  }

  /// Pastes the clipboard into the terminal (bracketed paste when the remote
  /// program enables it).
  Future<void> _onPaste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty) return;
    _terminal.paste(text);
  }

  void _disarmModifiers() {
    if (!_ctrlArmed && !_altArmed) return;
    setState(() {
      _ctrlArmed = false;
      _altArmed = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    ref.listen(sshShellControllerProvider(widget.serverId), (_, next) {
      if (next is SshShellConnected) {
        _wire(next.session);
      } else {
        _unwire();
      }
    });
    final state = ref.watch(sshShellControllerProvider(widget.serverId));
    // Only the live terminal adopts the terminal background; the connecting and
    // error states keep the app's normal surface so they match the rest of the
    // app.
    final terminalActive = state is SshShellConnected;
    return Scaffold(
      backgroundColor: terminalActive ? _terminalTheme.background : null,
      appBar: AppBar(
        title: Text(l10n.shellTitle),
        actions: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.link_off),
            tooltip: l10n.shellDisconnect,
          ),
        ],
      ),
      body: SafeArea(child: _body(context, l10n, state)),
    );
  }

  Widget _body(
    BuildContext context,
    AppLocalizations l10n,
    SshShellState state,
  ) {
    return switch (state) {
      SshShellConnecting() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: AppSpacing.lg),
            Text(l10n.shellConnecting),
          ],
        ),
      ),
      SshShellConnected() => Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              // TerminalView defaults to TerminalThemes.defaultTheme; the
              // Scaffold background above is kept in sync with it via
              // [_terminalTheme].
              child: TerminalView(
                _terminal,
                controller: _terminalController,
                autofocus: true,
                hardwareKeyboardOnly: _usesHardwareKeyboardOnly,
              ),
            ),
          ),
          ShellExtraKeysBar(
            ctrlActive: _ctrlArmed,
            altActive: _altArmed,
            onKey: _onBarKey,
            onChar: _onBarChar,
            onToggleCtrl: () => setState(() => _ctrlArmed = !_ctrlArmed),
            onToggleAlt: () => setState(() => _altArmed = !_altArmed),
            onCopy: _onCopy,
            onPaste: () => unawaited(_onPaste()),
          ),
        ],
      ),
      SshShellError(:final code) => EmptyState(
        icon: Icons.error_outline,
        title: l10n.shellError,
        message: localizedErrorMessage(l10n, code),
        action: Column(
          children: [
            PrimaryButton(
              label: l10n.shellRetry,
              icon: Icons.refresh,
              onPressed: () => ref
                  .read(sshShellControllerProvider(widget.serverId).notifier)
                  .retry(),
            ),
            ErrorHelpButton(code: code),
          ],
        ),
      ),
      SshShellClosed() => EmptyState(
        icon: Icons.link_off,
        title: l10n.shellDisconnected,
        action: PrimaryButton(
          label: l10n.shellRetry,
          icon: Icons.refresh,
          onPressed: () => ref
              .read(sshShellControllerProvider(widget.serverId).notifier)
              .retry(),
        ),
      ),
    };
  }
}
