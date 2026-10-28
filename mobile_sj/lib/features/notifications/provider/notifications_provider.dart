import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../accounts/data/account_service.dart';
import '../../asset_history/data/asset_history_service.dart';
import '../../asset_history/model/edit_request_model.dart';
import '../../auth/provider/auth_provider.dart';
import '../../dashboard/provider/dashboard_provider.dart';
import '../../../core/highlight/highlight_provider.dart';
import '../../settings/provider/settings_provider.dart';

/// The kind of action a notification asks for - the notifications screen filters by it (same
/// kinds, in the same order, as the web bell's filter).
enum NotificationCategory {
  reminder('Reminders'),
  approval('Approvals'),
  pending('Pending'),
  rejected('Rejected'),
  account('Accounts'),
  asset('Asset issues');

  final String label;
  const NotificationCategory(this.label);
}

/// One thing someone has to act on: the web dashboard's "Pending Approvals", "staff account has
/// no office" and "Needs attention" alerts. [key] identifies the kind of notification and [count]
/// how many there are, so a rise in the count is what makes it new.
class AppNotification {
  final String key;
  final int count;
  final IconData icon;
  final String title;
  final String detail;
  final String route;
  final bool warning; // amber (needs action) vs. red (something was refused or is broken)
  /// Plays the sound and shows the banner when it's new. Off for counts the user's own work
  /// changes (their own pending requests, asset data problems), which only mark the bell.
  final bool ping;
  /// The list [route] opens and the records there this notification is about, so that screen
  /// can highlight them (asset ids, "KIND-recordId" requests, or user ids).
  final HighlightTarget? highlightTarget;
  final List<String> highlightIds;
  NotificationCategory get category => switch (key) {
        _ when key.startsWith('reminder-') => NotificationCategory.reminder,
        'pending-approvals' => NotificationCategory.approval,
        'my-pending' => NotificationCategory.pending,
        'my-rejected' => NotificationCategory.rejected,
        'staff-no-office' => NotificationCategory.account,
        _ => NotificationCategory.asset,
      };

  const AppNotification({
    required this.key,
    required this.count,
    required this.icon,
    required this.title,
    required this.detail,
    required this.route,
    this.warning = true,
    this.ping = false,
    this.highlightTarget,
    this.highlightIds = const [],
  });
}

final notificationsProvider = FutureProvider.autoDispose<List<AppNotification>>((ref) async {
  final user = ref.watch(authProvider).valueOrNull;
  if (user == null) return const [];
  final items = <AppNotification>[];

  // The backend scopes /asset-history/requests: an admin gets every staff request,
  // a staff account only its own.
  var requests = const <EditRequestModel>[];
  try {
    // Admin-Staff may list everyone's requests; its reminders are about the ones it filed.
    requests = await AssetHistoryService().getRequests(userId: user.isAdminStaff ? user.id : null);
  } catch (_) {
    // leave it out rather than failing the whole list
  }

  String requestKey(EditRequestModel r) => '${r.kind}-${r.recordId}';

  if (user.isAdmin) {
    final pendingList = requests.where((r) => r.approvalStatus == 'PENDING_APPROVAL').toList();
    final pending = pendingList.length;
    // An Admin-Staff account's "Notify admin": one per request, newest reminder first. The count
    // is how many times it was reminded, so every new reminder makes it unread (and pings) again.
    final reminded = pendingList.where((r) => r.reminderCount > 0).toList()
      ..sort((a, b) => (b.lastRemindedAt ?? '').compareTo(a.lastRemindedAt ?? ''));
    for (final r in reminded) {
      final kind = switch (r.kind) { 'MAINTENANCE' => 'maintenance', 'DISPOSAL' => 'disposal', _ => 'transfer' };
      items.add(AppNotification(
        key: 'reminder-${requestKey(r)}',
        count: r.reminderCount,
        icon: Icons.notifications_active_rounded,
        title: 'Reminder: the $kind request for ${r.propertyNumber} is still waiting for approval',
        detail: 'Filed by ${r.requestedByName ?? 'staff'}. ${r.lastRemindedByName ?? 'Admin-Staff'} reminded you'
            '${r.reminderCount > 1 ? ' (${r.reminderCount} times)' : ''}.',
        route: '/asset-history?tab=requests',
        ping: true,
        highlightTarget: HighlightTarget.requests,
        highlightIds: [requestKey(r)],
      ));
    }
    if (pending > 0) {
      items.add(AppNotification(
        key: 'pending-approvals',
        count: pending,
        icon: Icons.pending_actions_rounded,
        title: '$pending ${pending == 1 ? 'request is' : 'requests are'} waiting for your approval',
        detail: 'Maintenance, disposal and transfer requests from staff.',
        route: '/asset-history?tab=requests',
        ping: true,
        highlightTarget: HighlightTarget.requests,
        highlightIds: pendingList.map(requestKey).toList(),
      ));
    }
    try {
      final accounts = await AccountService().getAll();
      final noOffice = accounts.where((a) => a.role == 'STAFF' && a.isActive && a.officeName == null).toList();
      if (noOffice.isNotEmpty) {
        final names = noOffice.take(2).map((a) => a.fullName).join(', ');
        items.add(AppNotification(
          key: 'staff-no-office',
          count: noOffice.length,
          icon: Icons.apartment_rounded,
          title: '${noOffice.length} staff ${noOffice.length == 1 ? 'account has' : 'accounts have'} no office assigned',
          detail: '$names${noOffice.length > 2 ? ' and others' : ''} can\'t see any assets until an office is assigned.',
          route: '/personnel?filter=no-office',
          ping: true,
          highlightTarget: HighlightTarget.accounts,
          highlightIds: [for (final a in noOffice) '${a.id}'],
        ));
      }
    } catch (_) {
      // the accounts list is a nice-to-have here
    }
  } else {
    // Staff: their own requests that were refused in the last two weeks, so they can fix and resend.
    final cutoff = DateTime.now().subtract(const Duration(days: 14));
    final rejectedList = requests.where((r) {
      if (r.approvalStatus != 'REJECTED') return false;
      final at = DateTime.tryParse(r.reviewedAt ?? r.requestedAt ?? '');
      return at == null || at.isAfter(cutoff);
    }).toList();
    final rejected = rejectedList.length;
    if (rejected > 0) {
      items.add(AppNotification(
        key: 'my-rejected',
        count: rejected,
        icon: Icons.block_rounded,
        title: rejected == 1 ? 'Your request was rejected' : '$rejected of your requests were rejected',
        detail: 'Open History to read the reason and fix it.',
        route: '/asset-history?tab=requests',
        warning: false,
        ping: true,
        highlightTarget: HighlightTarget.requests,
        highlightIds: rejectedList.map(requestKey).toList(),
      ));
    }
    final pendingList = requests.where((r) => r.approvalStatus == 'PENDING_APPROVAL').toList();
    final pending = pendingList.length;
    if (pending > 0) {
      items.add(AppNotification(
        key: 'my-pending',
        highlightTarget: HighlightTarget.requests,
        highlightIds: pendingList.map(requestKey).toList(),
        count: pending,
        icon: Icons.hourglass_top_rounded,
        title: pending == 1 ? 'Your request is waiting for approval' : '$pending of your requests are waiting for approval',
        detail: 'An administrator still has to review ${pending == 1 ? 'it' : 'them'}.',
        route: '/asset-history?tab=requests',
      ));
    }
  }

  // The web's asset problems, from the same dashboard summary (staff: their office only).
  try {
    final stats = await ref.watch(dashboardStatsProvider.future);
    String examples(DashboardAttention a) {
      final shown = a.items.take(2).map((x) => x.propertyNumber).join(', ');
      return a.count > 2 ? '$shown and ${a.count - 2} more' : shown;
    }
    String plural(int n, String one, String many) => '$n ${n == 1 ? one : many}';
    List<String> assetIds(DashboardAttention a) =>
        [for (final id in a.ids.isNotEmpty ? a.ids : a.items.map((x) => x.id)) '$id'];

    final unserviceable = stats.unserviceableNoDisposal;
    if (unserviceable.count > 0) {
      items.add(AppNotification(
        key: 'unserviceable-no-disposal',
        count: unserviceable.count,
        icon: Icons.report_rounded,
        title: '${plural(unserviceable.count, 'unserviceable asset has', 'unserviceable assets have')} no disposal record yet',
        detail: examples(unserviceable),
        route: '/assets',
        highlightTarget: HighlightTarget.assets,
        highlightIds: assetIds(unserviceable),
        warning: false,
      ));
    }
    final noAccountable = stats.noAccountable;
    if (noAccountable.count > 0) {
      items.add(AppNotification(
        key: 'no-accountable',
        count: noAccountable.count,
        icon: Icons.person_off_rounded,
        title: '${plural(noAccountable.count, 'asset has', 'assets have')} no accountable person',
        detail: examples(noAccountable),
        route: '/assets',
        highlightTarget: HighlightTarget.assets,
        highlightIds: assetIds(noAccountable),
      ));
    }
    final noOffice = stats.noOffice;
    if (user.isAdmin && noOffice.count > 0) {
      items.add(AppNotification(
        key: 'asset-no-office',
        count: noOffice.count,
        icon: Icons.domain_disabled_rounded,
        title: '${plural(noOffice.count, 'asset is', 'assets are')} not assigned to an office',
        detail: examples(noOffice),
        route: '/assets',
        highlightTarget: HighlightTarget.assets,
        highlightIds: assetIds(noOffice),
      ));
    }
  } catch (_) {
    // Home's totals already say when the summary couldn't load
  }
  return items;
});

/// What this account has already been told about, saved on the phone per account:
/// [seen] = the counts when the notifications screen was last opened (anything above is unread),
/// [known] = the counts at the last check (anything above is new, and pings).
/// A kind that drops out of a check (e.g. it failed to load) keeps its old count, so it doesn't
/// ping again when it comes back.
class NotificationMemory {
  final Map<String, int> seen;
  final Map<String, int> known;
  final bool firstCheck; // nothing saved yet for this account: take note, don't ping
  const NotificationMemory({this.seen = const {}, this.known = const {}, this.firstCheck = true});

  bool isUnread(AppNotification n) => n.count > (seen[n.key] ?? 0);
}

class NotificationMemoryNotifier extends Notifier<NotificationMemory> {
  String? get _user => ref.read(authProvider).valueOrNull?.username;
  String _prefKey(String user) => 'notifications.$user';

  @override
  NotificationMemory build() {
    final user = ref.watch(authProvider).valueOrNull?.username;
    if (user == null) return const NotificationMemory();
    final raw = ref.read(sharedPreferencesProvider).getString(_prefKey(user));
    if (raw == null) return const NotificationMemory();
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      Map<String, int> ints(Object? v) => {for (final e in ((v as Map?) ?? {}).entries) '${e.key}': (e.value as num).toInt()};
      return NotificationMemory(seen: ints(m['seen']), known: ints(m['known']), firstCheck: false);
    } catch (_) {
      return const NotificationMemory();
    }
  }

  void _save(NotificationMemory m) {
    state = m;
    final user = _user;
    if (user == null) return;
    ref.read(sharedPreferencesProvider).setString(_prefKey(user), jsonEncode({'seen': m.seen, 'known': m.known}));
  }

  /// Records a fresh check and returns the notifications that are new since the last one
  /// (none on this account's very first check).
  List<AppNotification> observe(List<AppNotification> items) {
    final m = state;
    final fresh = m.firstCheck ? const <AppNotification>[] : items.where((n) => n.count > (m.known[n.key] ?? 0)).toList();
    _save(NotificationMemory(seen: m.seen, known: {...m.known, for (final n in items) n.key: n.count}, firstCheck: false));
    return fresh;
  }

  /// The notifications screen was opened: everything on it is now read.
  void markAllSeen(List<AppNotification> items) {
    final m = state;
    if (items.every((n) => !m.isUnread(n))) return;
    _save(NotificationMemory(
      seen: {...m.seen, for (final n in items) n.key: n.count},
      known: {...m.known, for (final n in items) n.key: n.count},
      firstCheck: false,
    ));
  }
}

final notificationMemoryProvider =
    NotifierProvider<NotificationMemoryNotifier, NotificationMemory>(NotificationMemoryNotifier.new);

/// How many notifications are unread, for the bell's badge.
final unreadNotificationsProvider = Provider.autoDispose<int>((ref) {
  final items = ref.watch(notificationsProvider).valueOrNull ?? const [];
  final memory = ref.watch(notificationMemoryProvider);
  return items.where(memory.isUnread).length;
});

/// Goes up by one each time a new notification pings, so the bell can shake.
final notificationPingProvider = StateProvider<int>((ref) => 0);
