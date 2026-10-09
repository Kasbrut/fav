import 'package:fav/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

/// Termux-style extra-keys bar shown between the terminal and the soft
/// keyboard, providing the keys phone keyboards lack (ESC, TAB, CTRL, ALT,
/// arrows, HOME/END/PGUP/PGDN and the common `/` and `-`).
///
/// Pure presentation: every tap is reported through a callback and the sticky
/// CTRL/ALT state is owned by the parent, so the widget stays testable in
/// isolation. [ExcludeFocus] keeps the buttons out of the focus tree — a tap
/// must never steal focus from the terminal, or the soft keyboard would close.
class ShellExtraKeysBar extends StatelessWidget {
  /// Creates a [ShellExtraKeysBar].
  const ShellExtraKeysBar({
    required this.ctrlActive,
    required this.altActive,
    required this.onKey,
    required this.onChar,
    required this.onToggleCtrl,
    required this.onToggleAlt,
    required this.onCopy,
    required this.onPaste,
    super.key,
  });

  /// Whether the sticky CTRL modifier is armed (rendered highlighted).
  final bool ctrlActive;

  /// Whether the sticky ALT modifier is armed (rendered highlighted).
  final bool altActive;

  /// Called with the [TerminalKey] of a tapped special key.
  final ValueChanged<TerminalKey> onKey;

  /// Called with the literal character of a tapped character key.
  final ValueChanged<String> onChar;

  /// Called when the sticky CTRL key is tapped.
  final VoidCallback onToggleCtrl;

  /// Called when the sticky ALT key is tapped.
  final VoidCallback onToggleAlt;

  /// Called when the copy key is tapped (copies the terminal selection).
  final VoidCallback onCopy;

  /// Called when the paste key is tapped (pastes the clipboard).
  final VoidCallback onPaste;

  /// Matches the dark terminal background the shell screen always uses,
  /// independent of the app theme.
  static const Color _background = Color(0xFF1C2126);
  static const Color _foreground = Color(0xFFD3D7CF);

  /// Armed sticky modifiers must be unmistakable at a glance.
  static const Color _activeBackground = Color(0xFF3D5AFE);

  /// Pressed-state ink, bright enough to read on the dark background.
  static const Color _pressedInk = Colors.white24;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // Material (not ColoredBox) so the InkWell ripples actually render.
    return ExcludeFocus(
      child: Material(
        color: _background,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                _textKey(l10n.shellKeyEsc, () => onKey(TerminalKey.escape)),
                _textKey('/', () => onChar('/')),
                _textKey('-', () => onChar('-')),
                _textKey(l10n.shellKeyHome, () => onKey(TerminalKey.home)),
                _iconKey(
                  Icons.keyboard_arrow_up,
                  l10n.shellKeyUp,
                  () => onKey(TerminalKey.arrowUp),
                ),
                _textKey(l10n.shellKeyEnd, () => onKey(TerminalKey.end)),
                _textKey(l10n.shellKeyPgUp, () => onKey(TerminalKey.pageUp)),
                _iconKey(Icons.copy, l10n.shellKeyCopy, onCopy),
              ],
            ),
            Row(
              children: [
                _textKey(l10n.shellKeyTab, () => onKey(TerminalKey.tab)),
                _textKey(
                  l10n.shellKeyCtrl,
                  onToggleCtrl,
                  active: ctrlActive,
                  toggle: true,
                ),
                _textKey(
                  l10n.shellKeyAlt,
                  onToggleAlt,
                  active: altActive,
                  toggle: true,
                ),
                _iconKey(
                  Icons.keyboard_arrow_left,
                  l10n.shellKeyLeft,
                  () => onKey(TerminalKey.arrowLeft),
                ),
                _iconKey(
                  Icons.keyboard_arrow_down,
                  l10n.shellKeyDown,
                  () => onKey(TerminalKey.arrowDown),
                ),
                _iconKey(
                  Icons.keyboard_arrow_right,
                  l10n.shellKeyRight,
                  () => onKey(TerminalKey.arrowRight),
                ),
                _textKey(l10n.shellKeyPgDn, () => onKey(TerminalKey.pageDown)),
                _iconKey(Icons.content_paste, l10n.shellKeyPaste, onPaste),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// [toggle] marks the sticky modifier keys: only they expose a selected
  /// semantics state — a plain one-shot key must not, or screen readers would
  /// announce a spurious "not selected" on it.
  Widget _textKey(
    String label,
    VoidCallback onTap, {
    bool active = false,
    bool toggle = false,
  }) {
    return _key(
      onTap,
      active: active,
      semanticsSelected: toggle ? active : null,
      child: Text(
        label,
        style: TextStyle(
          // Pure white on the vivid active background keeps the label at
          // WCAG AA contrast; the resting grey would fall below 4.5:1 there.
          color: active ? Colors.white : _foreground,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _iconKey(IconData icon, String semanticsLabel, VoidCallback onTap) {
    return _key(
      onTap,
      child: Semantics(
        label: semanticsLabel,
        child: Icon(icon, size: 20, color: _foreground),
      ),
    );
  }

  Widget _key(
    VoidCallback onTap, {
    required Widget child,
    bool active = false,
    bool? semanticsSelected,
  }) {
    return Expanded(
      child: MergeSemantics(
        child: Semantics(
          button: true,
          selected: semanticsSelected,
          child: InkWell(
            onTap: onTap,
            splashColor: _pressedInk,
            highlightColor: _pressedInk,
            child: Ink(
              height: 40,
              color: active ? _activeBackground : Colors.transparent,
              child: Center(child: child),
            ),
          ),
        ),
      ),
    );
  }
}
