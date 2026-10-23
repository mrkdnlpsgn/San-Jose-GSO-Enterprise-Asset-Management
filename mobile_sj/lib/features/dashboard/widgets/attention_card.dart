import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import 'ios_style.dart';
import '../../accounts/data/account_service.dart';
import '../../asset_history/data/asset_history_service.dart';
import '../../asset_history/model/edit_request_model.dart';
import '../../auth/provider/auth_provider.dart';

/// Things on Home that someone has to act on - the web dashboard's "Pending Approvals"
/// and "staff account has no office" alerts. Shown only when there is something.
class AttentionItem {
  final IconData icon;
  final String title;
  final String detail;
  final String route;
  final bool warning; // amber (needs action) vs. red (something was refused)
  const AttentionItem(this.icon, this.title, this.detail, this.route, {this.warning = true});
}

final attentionProvider = FutureProvider.autoDispose<List<AttentionItem>>((ref) async {
  final user = ref.watch(authProvider).valueOrNull;
  if (user == null) return const [];
  final items = <AttentionItem>[];

  // The backend scopes /asset-history/requests: an admin gets every staff request,
  // a staff account only its own.
  var requests = const <EditRequestModel>[];
  try {
    requests = await AssetHistoryService().getRequests();
  } catch (_) {
    // leave the card empty rather than breaking Home
  }

  if (user.isAdmin) {
    final pending = requests.where((r) => r.approvalStatus == 'PENDING_APPROVAL').length;
    if (pending > 0) {
      items.add(AttentionItem(
        Icons.pending_actions_rounded,
        '$pending ${pending == 1 ? 'request is' : 'requests are'} waiting for your approval',
        'Maintenance, disposal and transfer requests from staff.',
        '/asset-history?tab=requests',
      ));
    }
    try {
      final accounts = await AccountService().getAll();
      final noOffice = accounts.where((a) => a.role == 'STAFF' && a.isActive && a.officeName == null).toList();
      if (noOffice.isNotEmpty) {
        final names = noOffice.take(2).map((a) => a.fullName).join(', ');
        items.add(AttentionItem(
          Icons.apartment_rounded,
          '${noOffice.length} staff ${noOffice.length == 1 ? 'account has' : 'accounts have'} no office assigned',
          '$names${noOffice.length > 2 ? ' and others' : ''} can\'t see any assets until an office is assigned.',
          '/personnel?filter=no-office',
        ));
      }
    } catch (_) {
      // the accounts list is a nice-to-have here - never block Home on it
    }
  } else {
    // Staff: their own requests that were refused in the last two weeks, so they can fix and resend.
    final cutoff = DateTime.now().subtract(const Duration(days: 14));
    final rejected = requests.where((r) {
      if (r.approvalStatus != 'REJECTED') return false;
      final at = DateTime.tryParse(r.reviewedAt ?? r.requestedAt ?? '');
      return at == null || at.isAfter(cutoff);
    }).length;
    if (rejected > 0) {
      items.add(AttentionItem(
        Icons.block_rounded,
        rejected == 1 ? 'Your request was rejected' : '$rejected of your requests were rejected',
        'Open History to read the reason and fix it.',
        '/asset-history?tab=requests',
        warning: false,
      ));
    }
    final pending = requests.where((r) => r.approvalStatus == 'PENDING_APPROVAL').length;
    if (pending > 0) {
      items.add(AttentionItem(
        Icons.hourglass_top_rounded,
        pending == 1 ? 'Your request is waiting for approval' : '$pending of your requests are waiting for approval',
        'An administrator still has to review ${pending == 1 ? 'it' : 'them'}.',
        '/asset-history?tab=requests',
      ));
    }
  }
  return items;
});

class AttentionCard extends ConsumerWidget {
  const AttentionCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(attentionProvider).valueOrNull ?? const [];
    if (items.isEmpty) return const SizedBox.shrink();
    final c = context.colors;

    // iOS grouped section: Settings-style rows - a solid system-colour icon tile, the text,
    // and a thin grey chevron; hairline separators inset to the text.
    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const IosSectionHeader('Needs your attention'),
          Card(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  if (i > 0) const Divider(height: 1, indent: 60),
                  PressScale(
                    scale: 0.98,
                    child: InkWell(
                      // History is a bottom-bar tab (switch to it); Personnel is a pushed screen
                      onTap: () =>
                          items[i].route.startsWith('/asset-history') ? context.go(items[i].route) : context.push(items[i].route),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 13, 14, 13),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            IosIconTile(icon: items[i].icon, color: items[i].warning ? Ios.orange : Ios.red),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(items[i].title,
                                      style: TextStyle(
                                          fontSize: 16.5,
                                          height: 1.3,
                                          fontWeight: FontWeight.w600,
                                          letterSpacing: -0.2,
                                          color: c.textPrimary)),
                                  const SizedBox(height: 2),
                                  Text(items[i].detail, style: TextStyle(fontSize: 14.5, height: 1.35, color: c.textSecondary)),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            const IosChevron(),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
