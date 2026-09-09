import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../../features/auth/provider/auth_provider.dart';

const _kWarnAfter = Duration(minutes: 14);
const _kCountdownSeconds = 60;

/// Mirrors the web app's 15-minute idle-logout (MainLayout.jsx: 14 minutes of
/// inactivity triggers a warning dialog with a 60-second countdown, then an
/// automatic sign-out). Wraps the whole app so any tap/drag anywhere resets
/// the timer; a `Listener` at the root catches pointer events regardless of
/// which screen is on top, mirroring web's window-level activity listeners.
/// Inert while logged out — no timers run on the login/legal screens.
class IdleTimeoutGuard extends ConsumerStatefulWidget {
  final Widget child;
  const IdleTimeoutGuard({super.key, required this.child});

  @override
  ConsumerState<IdleTimeoutGuard> createState() => _IdleTimeoutGuardState();
}

class _IdleTimeoutGuardState extends ConsumerState<IdleTimeoutGuard> {
  Timer? _warnTimer;
  Timer? _countdownTimer;
  int _secondsLeft = _kCountdownSeconds;
  bool _dialogShowing = false;

  @override
  void dispose() {
    _warnTimer?.cancel();
    _countdownTimer?.cancel();
    super.dispose();
  }

  bool get _isAuthenticated => ref.read(authProvider).value != null;

  void _onActivity() {
    if (_dialogShowing) return; // let the dialog's own buttons handle it
    if (!_isAuthenticated) return;
    _warnTimer?.cancel();
    _warnTimer = Timer(_kWarnAfter, _showWarning);
  }

  void _stopAllTimers() {
    _warnTimer?.cancel();
    _countdownTimer?.cancel();
  }

  void _showWarning() {
    if (!mounted || _dialogShowing) return;
    setState(() {
      _dialogShowing = true;
      _secondsLeft = _kCountdownSeconds;
    });
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      if (_secondsLeft <= 1) {
        t.cancel();
        _logout();
        return;
      }
      setState(() => _secondsLeft--);
    });
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _IdleWarningDialog(
        secondsLeft: () => _secondsLeft,
        onStay: () {
          Navigator.of(ctx).pop();
          setState(() => _dialogShowing = false);
          _stopAllTimers();
          _onActivity();
        },
        onLogoutNow: () {
          Navigator.of(ctx).pop();
          _logout();
        },
      ),
    );
  }

  void _logout() {
    _stopAllTimers();
    if (mounted) setState(() => _dialogShowing = false);
    // go_router's redirect listens to authProvider — clearing it here is
    // enough to bounce back to /login, no manual navigation needed.
    ref.read(authProvider.notifier).logout();
  }

  @override
  Widget build(BuildContext context) {
    // Starts/stops the idle clock as auth state actually changes (login,
    // logout elsewhere e.g. the manual logout button, session expiry via 401)
    // rather than only on pointer activity.
    ref.listen(authProvider, (previous, next) {
      if (next.value != null) {
        _onActivity();
      } else {
        _stopAllTimers();
        if (_dialogShowing && mounted) {
          Navigator.of(context, rootNavigator: true).maybePop();
          setState(() => _dialogShowing = false);
        }
      }
    });

    return Listener(
      onPointerDown: (_) => _onActivity(),
      onPointerMove: (_) => _onActivity(),
      onPointerSignal: (_) => _onActivity(),
      behavior: HitTestBehavior.translucent,
      child: widget.child,
    );
  }
}

class _IdleWarningDialog extends StatefulWidget {
  final int Function() secondsLeft;
  final VoidCallback onStay;
  final VoidCallback onLogoutNow;

  const _IdleWarningDialog({
    required this.secondsLeft,
    required this.onStay,
    required this.onLogoutNow,
  });

  @override
  State<_IdleWarningDialog> createState() => _IdleWarningDialogState();
}

class _IdleWarningDialogState extends State<_IdleWarningDialog> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // Own 1s ticker just to repaint the countdown text — the actual logout
    // timing is driven by the parent's _countdownTimer, not this one.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: context.colors.surface,
      title: Text('Session Expiring Soon', style: TextStyle(color: context.colors.textPrimary)),
      content: Text(
        "You've been inactive for a while. You'll be signed out in ${widget.secondsLeft()}s unless you choose to stay.",
        style: TextStyle(color: context.colors.textTertiary, fontSize: 13),
      ),
      actions: [
        TextButton(
          onPressed: widget.onLogoutNow,
          child: const Text('Log Out Now', style: TextStyle(color: Colors.red)),
        ),
        TextButton(
          onPressed: widget.onStay,
          child: const Text('Stay Logged In'),
        ),
      ],
    );
  }
}
