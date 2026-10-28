import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:san_jose_eam_mobile/core/router/app_router.dart';
import 'package:san_jose_eam_mobile/core/theme/app_theme.dart';
import 'package:san_jose_eam_mobile/features/auth/model/user_model.dart';
import 'package:san_jose_eam_mobile/features/auth/provider/auth_provider.dart';
import 'package:san_jose_eam_mobile/features/notifications/provider/notifications_provider.dart';
import 'package:san_jose_eam_mobile/features/notifications/screens/notifications_screen.dart';
import 'package:san_jose_eam_mobile/features/notifications/widgets/notification_bell.dart';
import 'package:san_jose_eam_mobile/features/notifications/widgets/notification_watcher.dart';
import 'package:san_jose_eam_mobile/features/settings/provider/settings_provider.dart';

AppNotification _n(String key, int count, {bool ping = true}) => AppNotification(
      key: key,
      count: count,
      icon: Icons.pending_actions_rounded,
      title: '$count $key',
      detail: 'detail',
      route: '/somewhere',
      ping: ping,
    );

class _FakeAuth extends AuthNotifier {
  @override
  Future<UserModel?> build() async => UserModel.fromJson({'userId': 1, 'username': 'admin', 'role': 'ADMIN'});
}

class _FakeSettings extends SettingsNotifier {
  @override
  SettingsState build() => const SettingsState(themeMode: ThemeMode.light, textSize: TextSizeOption.normal, serverAddress: '');
}

/// The notifications list, driven by the test.
final _items = StateProvider<List<AppNotification>>((ref) => const []);

Future<ProviderContainer> _container() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(overrides: [
    sharedPreferencesProvider.overrideWithValue(prefs),
    authProvider.overrideWith(_FakeAuth.new),
    settingsProvider.overrideWith(_FakeSettings.new),
    notificationsProvider.overrideWith((ref) async => ref.watch(_items)),
  ]);
  await container.read(authProvider.future);
  return container;
}

void main() {
  group('NotificationMemory', () {
    test('the first check only takes note; a rise in a count is new', () async {
      final c = await _container();
      final memory = c.read(notificationMemoryProvider.notifier);
      expect(memory.observe([_n('pending-approvals', 2)]), isEmpty);
      expect(memory.observe([_n('pending-approvals', 2)]), isEmpty);
      expect(memory.observe([_n('pending-approvals', 3)]).map((n) => n.count), [3]);
      expect(memory.observe([_n('pending-approvals', 1)]), isEmpty); // going down is not news
      // ...but back up again is: two requests were approved, then two new ones came in
      expect(memory.observe([_n('pending-approvals', 3), _n('staff-no-office', 1)]).map((n) => n.key),
          ['pending-approvals', 'staff-no-office']);
    });

    test('a kind that drops out of a check does not ping again when it comes back', () async {
      final c = await _container();
      final memory = c.read(notificationMemoryProvider.notifier);
      memory.observe([_n('pending-approvals', 2)]);
      memory.observe(const []); // e.g. the requests failed to load
      expect(memory.observe([_n('pending-approvals', 2)]), isEmpty);
    });

    test('everything is unread until the screen is opened, and it is saved per account', () async {
      final c = await _container();
      c.read(_items.notifier).state = [_n('pending-approvals', 2), _n('no-accountable', 5, ping: false)];
      await c.read(notificationsProvider.future);
      final sub = c.listen(unreadNotificationsProvider, (_, __) {});
      expect(sub.read(), 2);
      c.read(notificationMemoryProvider.notifier).markAllSeen(c.read(_items));
      expect(sub.read(), 0);
      expect(c.read(sharedPreferencesProvider).getString('notifications.admin'), contains('"seen"'));

      c.read(_items.notifier).state = [_n('pending-approvals', 4), _n('no-accountable', 5, ping: false)];
      await c.read(notificationsProvider.future);
      expect(sub.read(), 1);
    });
  });

  testWidgets('bell badge, then the screen marks everything read', (tester) async {
    final c = await _container();
    c.read(_items.notifier).state = [_n('pending-approvals', 2), _n('staff-no-office', 1)];
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, __) => const Scaffold(body: Center(child: NotificationBell()))),
      GoRoute(path: '/notifications', builder: (_, __) => const NotificationsScreen()),
    ]);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
    ));
    await tester.pumpAndSettle();
    expect(find.text('2'), findsOneWidget);
    expect(find.bySemanticsLabel('Notifications, 2 unread'), findsOneWidget);

    await tester.tap(find.byType(NotificationBell));
    await tester.pumpAndSettle();
    expect(find.text('2 pending-approvals'), findsOneWidget);
    expect(find.text('NEW'), findsNWidgets(2)); // still marked while the screen is open
    expect(c.read(unreadNotificationsProvider), 0);

    router.pop();
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Notifications'), findsOneWidget);
  });

  testWidgets('a new notification shows the banner; one from the user\'s own work does not', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, __) => const Scaffold(body: Center(child: NotificationBell()))),
      GoRoute(path: '/notifications', builder: (_, __) => const Scaffold(body: Text('notifications screen'))),
    ]);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    // A ProviderScope owned by the widget tree (cleans up on frames, not on leftover timers)
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        authProvider.overrideWith(_FakeAuth.new),
        settingsProvider.overrideWith(_FakeSettings.new),
        notificationsProvider.overrideWith((ref) async => ref.watch(_items)),
        appRouterProvider.overrideWithValue(router),
      ],
      child: MaterialApp.router(
        theme: AppTheme.light,
        routerConfig: router,
        builder: (context, child) => NotificationWatcher(child: child!),
      ),
    ));
    final c = ProviderScope.containerOf(tester.element(find.byType(NotificationWatcher)));
    c.read(_items.notifier).state = [_n('pending-approvals', 1)];
    await tester.pumpAndSettle();
    expect(find.text('Tap to view.'), findsNothing); // first check: just taking note

    c.read(_items.notifier).state = [_n('pending-approvals', 1), _n('no-accountable', 9, ping: false)];
    await tester.pumpAndSettle();
    expect(find.text('Tap to view.'), findsNothing);

    c.read(_items.notifier).state = [_n('pending-approvals', 3), _n('no-accountable', 9, ping: false)];
    await tester.pumpAndSettle(); // the banner slides in
    expect(find.text('3 pending-approvals'), findsOneWidget);
    expect(find.text('Tap to view.'), findsOneWidget);

    await tester.tap(find.text('3 pending-approvals'));
    await tester.pumpAndSettle();
    expect(find.text('notifications screen'), findsOneWidget);
    expect(find.text('Tap to view.'), findsNothing);
  });
}
