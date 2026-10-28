import 'dart:math' as math;

import 'package:flutter/cupertino.dart' show CupertinoButton;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/ios_touch.dart';
import '../provider/notifications_provider.dart';

/// Home's bell: a red badge with the number of unread notifications, and a short shake
/// each time a new one pings. Opens the notifications screen.
class NotificationBell extends ConsumerStatefulWidget {
  const NotificationBell({super.key});

  @override
  ConsumerState<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends ConsumerState<NotificationBell> with SingleTickerProviderStateMixin {
  late final _shake = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));

  @override
  void dispose() {
    _shake.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(notificationPingProvider, (_, __) {
      if (!MediaQuery.of(context).disableAnimations) _shake.forward(from: 0);
    });
    final unread = ref.watch(unreadNotificationsProvider);
    final c = context.colors;

    return Semantics(
      button: true,
      label: unread == 0 ? 'Notifications' : 'Notifications, $unread unread',
      excludeSemantics: true,
      child: PressScale(
        scale: 0.9,
        child: CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: const Size(44, 44),
          onPressed: () => context.push('/notifications'),
          child: SizedBox(
            width: 40,
            height: 40,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                AnimatedBuilder(
                  animation: _shake,
                  // swings from the top like a ringing bell, fading out
                  builder: (_, child) => Transform.rotate(
                    angle: math.sin(_shake.value * math.pi * 6) * 0.35 * (1 - _shake.value),
                    alignment: Alignment.topCenter,
                    child: child,
                  ),
                  child: Icon(unread > 0 ? Icons.notifications_rounded : Icons.notifications_none_rounded,
                      size: 28, color: c.textPrimary),
                ),
                if (unread > 0)
                  Positioned(
                    top: 1,
                    right: 0,
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF3B30),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Theme.of(context).scaffoldBackgroundColor, width: 2),
                      ),
                      child: Text(unread > 9 ? '9+' : '$unread',
                          textScaler: TextScaler.noScaling, // the badge must stay inside its circle
                          style: const TextStyle(color: Colors.white, fontSize: 12, height: 1.1, fontWeight: FontWeight.w700)),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
