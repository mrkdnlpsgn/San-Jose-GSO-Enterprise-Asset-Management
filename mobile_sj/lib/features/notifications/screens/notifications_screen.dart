import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../dashboard/widgets/ios_style.dart';
import '../provider/notifications_provider.dart';

/// Everything that needs the signed-in account's attention (what used to be Home's
/// "Needs your attention"), opened from the bell. Opening it marks everything as read;
/// the ones that were unread keep their "New" mark until the screen is closed.
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  Set<String>? _unreadOnOpen; // the keys that were new when the screen opened

  void _open(String route) {
    // History and Assets are bottom-bar tabs (switch to them); Personnel is a pushed screen
    route.startsWith('/asset-history') || route == '/assets' ? context.go(route) : context.push(route);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final async = ref.watch(notificationsProvider);
    final items = async.valueOrNull;

    if (items != null && _unreadOnOpen == null) {
      final memory = ref.read(notificationMemoryProvider);
      _unreadOnOpen = {for (final n in items) if (memory.isUnread(n)) n.key};
      // after this frame: changing the memory while building would rebuild the bell mid-frame
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.read(notificationMemoryProvider.notifier).markAllSeen(items);
      });
    }

    return Theme(
      data: Ios.theme(context),
      child: Builder(builder: (context) {
        return Scaffold(
          backgroundColor: Ios.groupedBg(context),
          appBar: AppBar(title: const Text('Notifications')),
          body: RefreshIndicator(
            onRefresh: () async => ref.refresh(notificationsProvider.future),
            child: items == null
                ? ListView(children: [
                    Padding(
                      padding: const EdgeInsets.all(32),
                      child: Center(
                        child: async.hasError
                            ? Text("Couldn't load notifications. Pull down to try again.",
                                textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: c.textSecondary))
                            : const CircularProgressIndicator(),
                      ),
                    ),
                  ])
                : items.isEmpty
                    ? ListView(children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(32, 64, 32, 32),
                          child: Column(children: [
                            Icon(Icons.notifications_none_rounded, size: 48, color: c.textTertiary),
                            const SizedBox(height: 12),
                            Text('No notifications',
                                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600, color: c.textPrimary)),
                            const SizedBox(height: 6),
                            Text('Anything that needs your attention will show here.',
                                textAlign: TextAlign.center, style: TextStyle(fontSize: 16, height: 1.4, color: c.textSecondary)),
                          ]),
                        ),
                      ])
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                        children: [
                          Card(
                            margin: EdgeInsets.zero,
                            clipBehavior: Clip.antiAlias,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                for (var i = 0; i < items.length; i++) ...[
                                  if (i > 0) const Divider(height: 1, indent: 60),
                                  _NotificationRow(
                                    item: items[i],
                                    isNew: _unreadOnOpen?.contains(items[i].key) ?? false,
                                    onTap: () => _open(items[i].route),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
          ),
        );
      }),
    );
  }
}

class _NotificationRow extends StatelessWidget {
  final AppNotification item;
  final bool isNew;
  final VoidCallback onTap;
  const _NotificationRow({required this.item, required this.isNew, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return PressScale(
      scale: 0.98,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 13, 14, 13),
          child: Row(
            children: [
              IosIconTile(icon: item.icon, color: item.warning ? Ios.orange : Ios.red),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isNew)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 3),
                        child: Text('NEW',
                            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, letterSpacing: 0.4, color: Ios.blue)),
                      ),
                    Text(item.title,
                        style: TextStyle(
                            fontSize: 16.5, height: 1.3, fontWeight: FontWeight.w600, letterSpacing: -0.2, color: c.textPrimary)),
                    const SizedBox(height: 2),
                    Text(item.detail, style: TextStyle(fontSize: 14.5, height: 1.35, color: c.textSecondary)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const DisclosureChevron(),
            ],
          ),
        ),
      ),
    );
  }
}
