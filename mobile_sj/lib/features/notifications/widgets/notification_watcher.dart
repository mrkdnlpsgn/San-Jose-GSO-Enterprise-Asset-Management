import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/platform/notification_sound.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/auto_refresh_ticker.dart';
import '../../auth/provider/auth_provider.dart';
import '../../dashboard/widgets/ios_style.dart';
import '../../settings/provider/settings_provider.dart';
import '../provider/notifications_provider.dart';

/// Wraps the whole app (main.dart). While someone is signed in and the app is open, it checks
/// for notifications every minute (and on returning to the app). When one is new it pings: the
/// phone's notification sound (which follows silent mode, and the Settings switch), a short
/// vibration, the bell's shake, and a banner at the top that opens the notifications screen.
class NotificationWatcher extends ConsumerStatefulWidget {
  final Widget child;
  const NotificationWatcher({super.key, required this.child});

  @override
  ConsumerState<NotificationWatcher> createState() => _NotificationWatcherState();
}

class _NotificationWatcherState extends ConsumerState<NotificationWatcher> {
  AppNotification? _banner;
  int _more = 0; // other new ones in the same check
  Timer? _hide;

  @override
  void dispose() {
    _hide?.cancel();
    super.dispose();
  }

  void _ping(List<AppNotification> fresh) {
    if (ref.read(settingsProvider).notificationSound) {
      NotificationSound.play();
    }
    HapticFeedback.vibrate();
    ref.read(notificationPingProvider.notifier).state++;
    _hide?.cancel();
    setState(() {
      _banner = fresh.first;
      _more = fresh.length - 1;
    });
    _hide = Timer(const Duration(seconds: 6), _dismiss);
  }

  void _dismiss() {
    _hide?.cancel();
    if (mounted && _banner != null) setState(() => _banner = null);
  }

  @override
  Widget build(BuildContext context) {
    final signedIn = ref.watch(authProvider.select((a) => a.valueOrNull != null));
    if (signedIn) {
      // listening also keeps the list loaded while no screen shows it
      ref.listen<AsyncValue<List<AppNotification>>>(notificationsProvider, (_, next) {
        final items = next.valueOrNull;
        if (items == null || next.isLoading) return;
        final fresh = ref.read(notificationMemoryProvider.notifier).observe(items).where((n) => n.ping).toList();
        if (fresh.isNotEmpty) _ping(fresh);
      });
    }

    return AutoRefreshTicker(
      interval: const Duration(minutes: 1),
      onTick: () {
        if (ref.read(authProvider).valueOrNull != null) ref.invalidate(notificationsProvider);
      },
      child: Stack(
        children: [
          widget.child,
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                transitionBuilder: (child, animation) => SlideTransition(
                  position: Tween(begin: const Offset(0, -1.2), end: Offset.zero)
                      .animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
                  child: FadeTransition(opacity: animation, child: child),
                ),
                child: _banner == null
                    ? const SizedBox.shrink()
                    : _Banner(
                        key: ValueKey('${_banner!.key}:${_banner!.count}'),
                        item: _banner!,
                        more: _more,
                        onTap: () {
                          _dismiss();
                          ref.read(appRouterProvider).push('/notifications');
                        },
                        onClose: _dismiss,
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  final AppNotification item;
  final int more;
  final VoidCallback onTap;
  final VoidCallback onClose;
  const _Banner({super.key, required this.item, required this.more, required this.onTap, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 0),
      child: Semantics(
        liveRegion: true,
        child: Dismissible(
          key: const ValueKey('notification-banner'),
          direction: DismissDirection.up,
          onDismissed: (_) => onClose(),
          child: Material(
            color: c.surface,
            elevation: 6,
            shadowColor: Colors.black38,
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
                child: Row(
                  children: [
                    IosIconTile(icon: item.icon, color: item.warning ? Ios.orange : Ios.red, size: 36),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(item.title,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 16, height: 1.3, fontWeight: FontWeight.w600, color: c.textPrimary)),
                          const SizedBox(height: 2),
                          Text(more > 0 ? 'And $more more. Tap to view.' : 'Tap to view.',
                              style: TextStyle(fontSize: 14.5, color: c.textSecondary)),
                        ],
                      ),
                    ),
                    // no tooltip: the banner sits above the navigator, where there's no overlay for one
                    Semantics(
                      label: 'Close',
                      button: true,
                      excludeSemantics: true,
                      child: IconButton(onPressed: onClose, icon: Icon(Icons.close_rounded, color: c.textTertiary)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
