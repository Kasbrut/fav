import 'dart:async';

import 'package:fav/core/theme/app_dimens.dart';
import 'package:fav/features/settings/application/app_lock_controller.dart';
import 'package:fav/features/settings/application/preferences_controller.dart';
import 'package:fav/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PredictiveBackEvent;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Replaces the whole app UI with a lock screen while the app lock is
/// engaged. Mounted in `MaterialApp.router`'s `builder:` so it covers every
/// route and overlay; `BootFailureApp` is deliberately not gated (the
/// recovery path must not depend on the preferences box or a plugin).
class AppLockGate extends ConsumerStatefulWidget {
  /// Creates the gate around the router's [child].
  const AppLockGate({required this.child, this.now, super.key});

  /// The routed app content shown while unlocked.
  final Widget child;

  /// Clock override used by lifecycle tests.
  final DateTime Function()? now;

  @override
  ConsumerState<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends ConsumerState<AppLockGate>
    with WidgetsBindingObserver {
  /// Visual-only privacy shield. Frames stop rendering once the lifecycle
  /// reaches hidden/paused, so the OS task-switcher snapshot captures the
  /// LAST rendered frame — the `inactive` one. The shield covers that frame;
  /// the real lock only engages on hidden/paused.
  bool _obscured = false;

  /// One auto-prompt per lock episode: armed on launch and whenever the
  /// controller actually locks, spent on the first prompt. A canceled
  /// prompt must not re-open itself on the `resumed` that follows — the
  /// button is the retry.
  bool _autoPrompted = false;
  DateTime? _focusLostAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAutoPrompt());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      // Never lock on `inactive`: the notification shade, permission
      // dialogs and the auth prompt itself all pass through it — only
      // shield the content so the snapshot never shows server data.
      case AppLifecycleState.inactive:
        _setObscured(true);
        _focusLostAt ??= _now();
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        _setObscured(true);
      case AppLifecycleState.resumed:
        _lockIfExpired();
        _focusLostAt = null;
        _setObscured(false);
        _maybeAutoPrompt();
      case AppLifecycleState.detached:
        break;
    }
  }

  void _lockIfExpired() {
    final lostAt = _focusLostAt;
    if (lostAt == null) return;
    final preferences = ref.read(preferencesControllerProvider);
    if (!preferences.appLockEnabled) return;
    final delay = preferences.appLockTimeout.duration;
    if (delay == null || _now().difference(lostAt) < delay) return;
    if (ref.read(appLockControllerProvider.notifier).lock()) {
      _autoPrompted = false;
    }
  }

  DateTime _now() => widget.now?.call() ?? DateTime.now();

  void _setObscured(bool value) {
    if (_obscured == value || !mounted) return;
    setState(() => _obscured = value);
  }

  void _maybeAutoPrompt() {
    if (_autoPrompted) return;
    if (!mounted) return;
    if (ref.read(appLockControllerProvider) != AppLockState.locked) return;
    _autoPrompted = true;
    _tryUnlock();
  }

  void _tryUnlock() {
    if (!mounted) return;
    if (ref.read(appLockControllerProvider) != AppLockState.locked) return;
    final l10n = AppLocalizations.of(context)!;
    unawaited(
      ref.read(appLockControllerProvider.notifier).unlock(l10n.appLockReason),
    );
  }

  /// Whether the overlay currently hides the content. Kept in sync by
  /// [build]; consulted from binding callbacks such as [didPopRoute].
  bool _covered = false;

  @override
  Future<bool> didPopRoute() async {
    // Swallow the Android back button while covered: the Router stays
    // mounted behind the overlay and the back-button dispatcher is a
    // binding observer, not a widget — without this the press would
    // navigate the hidden app (verify pass NEW-2).
    return _covered;
  }

  // Android 15+ predictive back bypasses didPopRoute: the dispatcher polls
  // handleStartBackGesture and falls back to a plain pop only when NO
  // observer claims the gesture. While covered, claim it and drop it —
  // otherwise the route transition's own detector drives the hidden Router
  // (verify pass LOW-4). The gate registers before the Router (parent
  // initState runs first), so it gets first refusal.
  @override
  bool handleStartBackGesture(PredictiveBackEvent backEvent) => _covered;

  @override
  void handleUpdateBackGestureProgress(PredictiveBackEvent backEvent) {}

  @override
  void handleCommitBackGesture() {}

  @override
  void handleCancelBackGesture() {}

  @override
  Widget build(BuildContext context) {
    final lockState = ref.watch(appLockControllerProvider);
    final lockEnabled = ref.watch(
      preferencesControllerProvider.select((p) => p.appLockEnabled),
    );
    final lockShown = lockState != AppLockState.unlocked;
    final covered = _covered = lockShown || (_obscured && lockEnabled);
    // Cover, never unmount: replacing the child would tear down the whole
    // Router subtree — open dialogs, shell sessions, autoDispose
    // controllers — on every transient `inactive`. Offstage neither paints
    // nor hit-tests and drops semantics; focus is excluded explicitly so a
    // hardware keyboard cannot type into covered content.
    return Stack(
      fit: StackFit.expand,
      children: [
        Offstage(
          offstage: covered,
          child: TickerMode(
            enabled: !covered,
            child: ExcludeFocus(excluding: covered, child: widget.child),
          ),
        ),
        if (lockShown)
          _AppLockScreen(
            unlocking: lockState == AppLockState.unlocking,
            onUnlock: _tryUnlock,
          )
        else if (covered)
          const _PrivacyShield(),
      ],
    );
  }
}

/// Icon-only cover shown on `inactive` while the app lock is enabled — the
/// frame the OS snapshot captures. No text, no actions: it is not the lock.
class _PrivacyShield extends StatelessWidget {
  const _PrivacyShield();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Material, NOT Scaffold — see _AppLockScreen (verify pass NEW-1):
    // this frame is exactly the one the OS snapshot captures.
    return Material(
      color: theme.scaffoldBackgroundColor,
      child: Center(
        child: Icon(
          Icons.lock_outline,
          size: 64,
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

class _AppLockScreen extends StatelessWidget {
  const _AppLockScreen({required this.unlocking, required this.onUnlock});

  final bool unlocking;
  final VoidCallback onUnlock;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    // Material, NOT Scaffold: a Scaffold registers with the app's
    // ScaffoldMessenger, which would replay content snackbars (peer
    // labels, error strings) on top of the lock (verify pass NEW-1).
    return Material(
      color: theme.scaffoldBackgroundColor,
      child: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.lock_outline,
                size: 64,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                l10n.appLockLockedTitle,
                style: theme.textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.xl),
              FilledButton.icon(
                onPressed: unlocking ? null : onUnlock,
                icon: const Icon(Icons.lock_open),
                label: Text(l10n.appLockUnlockButton),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
