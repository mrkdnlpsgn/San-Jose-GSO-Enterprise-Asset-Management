import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../auth/provider/auth_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/status_badge.dart';
import '../../../shared/widgets/section_card.dart';
import '../../../shared/widgets/skeleton.dart';
import '../../../shared/widgets/staggered_entrance.dart';
import '../../../shared/widgets/main_shell.dart';
import '../../../shared/widgets/auto_refresh_ticker.dart';
import '../../../shared/widgets/logout_dialog.dart';
import '../../assets/provider/ai_recommendation_provider.dart';
import '../../audit_log/provider/audit_log_digest_provider.dart';
import '../provider/dashboard_provider.dart';
import '../widgets/home_header.dart';
import '../widgets/attention_card.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).value;
    final isAdmin = user?.isAdmin ?? false;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: context.colors.border),
              ),
              child: const ClipOval(
                child: Image(image: AssetImage('assets/images/images.png'), fit: BoxFit.cover),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('San Jose GSO', style: TextStyle(fontSize: 17, height: 1.15)),
                  Text(
                    'Inventory Management System',
                    style: TextStyle(fontSize: 14, height: 1.2, fontWeight: FontWeight.w500, color: context.colors.textTertiary),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          // worded, not just an icon — clearer for staff who don't read icons
          TextButton.icon(
            icon: const Icon(Icons.logout_rounded, size: 20),
            label: const Text('Sign out'),
            style: TextButton.styleFrom(foregroundColor: context.colors.textSecondary),
            onPressed: () async {
              final confirmed = await showLogoutDialog(context);
              if (confirmed == true) ref.read(authProvider.notifier).logout();
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: AutoRefreshTicker(
        interval: const Duration(seconds: 30),
        onTick: () {
          ref.invalidate(dashboardStatsProvider);
          ref.invalidate(aiRecommendationSummaryProvider);
          ref.invalidate(auditLogDigestProvider);
          ref.invalidate(attentionProvider);
        },
        child: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(dashboardStatsProvider);
          ref.invalidate(aiRecommendationSummaryProvider);
          ref.invalidate(auditLogDigestProvider);
          ref.invalidate(attentionProvider);
        },
        child: ListView(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 24 + context.mainShellBottomInset),
        children: [
          // who is signed in + date/time, then anything waiting on them, then the shortcuts
          const HomeHeader(),
          const AttentionCard(),
          const SizedBox(height: 20),
          _DashboardStatsSection(modules: _ModuleList(isAdmin: isAdmin)),
        ],
        ),
      ),
      ),
    );
  }
}

/// Every other module, as a grid of round shortcuts (eGovPH home-screen style).
class _ModuleList extends StatelessWidget {
  final bool isAdmin;
  const _ModuleList({required this.isAdmin});

  @override
  Widget build(BuildContext context) {
    final items = <_ModuleItem>[
      const _ModuleItem(Icons.build_rounded, 'Maintenance', 'Repairs and maintenance records', '/maintenance'),
      const _ModuleItem(Icons.delete_rounded, 'Disposal', 'Disposal records', '/disposal'),
      const _ModuleItem(Icons.swap_horiz_rounded, 'Transfer', 'Move an asset to another office, and transfer requests', '/transfers'),
      const _ModuleItem(Icons.bar_chart_rounded, 'Reports', 'Inventory reports, RPCPPE, IIRUP and more', '/reports'),
      // Asset History is a bottom-bar tab (History), so it isn't repeated here.
      // Reference data, account management and the recycle bin are ADMIN-only —
      // staff work only with their office's assets, maintenance, disposal and reports.
      if (isAdmin) ...const [
        _ModuleItem(Icons.apartment_rounded, 'Offices', 'Offices and their head users', '/offices'),
        _ModuleItem(Icons.category_rounded, 'Categories', 'Asset categories', '/categories'),
        _ModuleItem(Icons.people_rounded, 'Accounts', 'Create and manage user accounts', '/accounts'),
        _ModuleItem(Icons.restore_from_trash_rounded, 'Recycle Bin', 'Restore deleted records', '/recycle-bin'),
      ],
    ];
    // eGovPH-style shortcuts: a round tinted tile with the icon, the name underneath.
    // A wrapping grid (4 per row on phones) rather than eGovPH's sideways-scrolling row,
    // so every module is visible at once — a half-hidden last icon is easy to miss.
    return LayoutBuilder(builder: (context, box) {
      final perRow = box.maxWidth >= 560 ? 6 : 4;
      final cellWidth = box.maxWidth / perRow;
      return Wrap(
        runSpacing: 14,
        children: [
          for (final item in items)
            SizedBox(width: cellWidth, child: _ModuleShortcut(item: item)),
        ],
      );
    });
  }
}

class _ModuleShortcut extends StatelessWidget {
  final _ModuleItem item;
  const _ModuleShortcut({required this.item});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final light = context.isLight;
    return Semantics(
      button: true,
      label: '${item.title}. ${item.subtitle}',
      excludeSemantics: true,
      child: InkWell(
        onTap: () => context.push(item.route),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
          child: Column(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  // pale navy circle (web gov-50), like eGovPH's pale blue tiles
                  color: light ? const Color(0xFFEEF2F8) : const Color(0xFF1E2533),
                  shape: BoxShape.circle,
                  border: Border.all(color: light ? const Color(0xFFD7E1F0) : c.border),
                ),
                child: Icon(item.icon, size: 30, color: light ? AppTheme.gov : const Color(0xFFB0C4E3)),
              ),
              const SizedBox(height: 8),
              // two-word names wrap onto two lines; a single long word ("Maintenance") shrinks a
              // little to fit instead of being split mid-word at the Large text size
              if (item.title.contains(' '))
                Text(
                  item.title,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14, height: 1.2, fontWeight: FontWeight.w600, color: c.textPrimary),
                )
              else
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    item.title,
                    maxLines: 1,
                    style: TextStyle(fontSize: 14, height: 1.2, fontWeight: FontWeight.w600, color: c.textPrimary),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModuleItem {
  final IconData icon;
  final String title;
  final String subtitle;
  final String route;
  const _ModuleItem(this.icon, this.title, this.subtitle, this.route);
}

String _fmtMoney(double v) {
  if (v >= 1000000) return '₱${(v / 1000000).toStringAsFixed(1)}M';
  if (v >= 1000) return '₱${(v / 1000).toStringAsFixed(0)}K';
  return '₱${v.toStringAsFixed(0)}';
}

const _conditionOrder = ['SERVICEABLE', 'REPAIRABLE', 'UNSERVICEABLE'];
// Registered+Assigned merged into one bucket (every asset has a location by
// default); maintenance/disposal are ledger-record buckets, not asset
// lifecycleStatus — see dashboard_provider.dart. Keep in sync with web's
// LIFECYCLE_CFG (frontend_sj/frontend/src/pages/Dashboard/index.jsx).
const _lifecycleOrder = [
  'REGISTERED', 'TRANSFERRED',
  'MAINT_ONGOING', 'MAINT_SCHEDULED', 'MAINT_REPAIRED',
  'DISP_PENDING', 'DISP_TRANSFERRED', 'DISP_DESTRUCTED',
  'ARCHIVED',
];
const _recommendationOrder = ['MAINTAIN', 'REPAIR', 'MONITOR', 'REVIEW_FOR_DISPOSAL', 'BUDGET_PRIORITY'];

Color _lifecycleDashboardColor(String key) => switch (key) {
      'REGISTERED' => const Color(0xFF3B82F6),
      'TRANSFERRED' => const Color(0xFFF97316),
      'MAINT_ONGOING' => const Color(0xFFF59E0B),
      'MAINT_SCHEDULED' => const Color(0xFFEAB308),
      'MAINT_REPAIRED' => const Color(0xFF84CC16),
      'DISP_PENDING' => const Color(0xFFFB7185),
      'DISP_TRANSFERRED' => const Color(0xFFEC4899),
      'DISP_DESTRUCTED' => const Color(0xFFDC2626),
      'ARCHIVED' => Colors.grey.shade600,
      _ => Colors.grey,
    };

String _lifecycleDashboardLabel(String key) => switch (key) {
      'REGISTERED' => 'Registered',
      'TRANSFERRED' => 'Transferred',
      'MAINT_ONGOING' => 'Ongoing Maintenance',
      'MAINT_SCHEDULED' => 'Scheduled Maintenance',
      'MAINT_REPAIRED' => 'Repaired',
      'DISP_PENDING' => 'Pending Disposal',
      'DISP_TRANSFERRED' => 'Transferred Disposal',
      'DISP_DESTRUCTED' => 'Destructed',
      'ARCHIVED' => 'Archived',
      _ => key,
    };

Color _recColor(String rec) => switch (rec) {
      'MAINTAIN' => AppTheme.brand,
      'REPAIR' => AppTheme.statusMaintenance,
      'MONITOR' => AppTheme.info,
      'REVIEW_FOR_DISPOSAL' => AppTheme.statusDisposed,
      'BUDGET_PRIORITY' => Colors.deepOrange,
      _ => Colors.grey,
    };

String _recLabel(String rec) => switch (rec) {
      'MAINTAIN' => 'Maintain',
      'REPAIR' => 'Repair',
      'MONITOR' => 'Monitor',
      'REVIEW_FOR_DISPOSAL' => 'Review for Disposal',
      'BUDGET_PRIORITY' => 'Budget Priority',
      _ => rec,
    };

class _DashboardStatsSection extends ConsumerStatefulWidget {
  final Widget modules;
  const _DashboardStatsSection({required this.modules});

  @override
  ConsumerState<_DashboardStatsSection> createState() => _DashboardStatsSectionState();
}

class _DashboardStatsSectionState extends ConsumerState<_DashboardStatsSection> {
  DashboardStats? _lastStats;
  bool _hasAnimatedIn = false;

  @override
  Widget build(BuildContext context) {
    final statsAsync = ref.watch(dashboardStatsProvider);
    final isAdmin = ref.watch(authProvider).value?.isAdmin ?? false;

    if (statsAsync.hasValue) _lastStats = statsAsync.value;
    // Keep rendering the last snapshot while a refresh is in flight instead
    // of dropping back to the skeleton — a pull-to-refresh would otherwise
    // tear down and recreate every card, replaying the stagger entrance and
    // restarting the count-up/ring animations from zero on data the user is
    // already looking at.
    final stats = _lastStats;

    // The module list doesn't depend on the stats — show it straight away, even while loading.
    Widget withModules(Widget overview, Widget charts) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // shortcuts first, as on eGovPH's home screen — getting around comes before the numbers
            widget.modules,
            const SizedBox(height: 24),
            const SectionLabel('Overview'),
            overview,
            const SizedBox(height: 24),
            const SectionLabel('Summary'),
            charts,
          ],
        );

    if (stats == null) {
      return statsAsync.when(
        loading: () => withModules(
          const Shimmer(child: _OverviewPanelSkeleton()),
          Shimmer(
            child: Column(
              children: [
                const _RingCardSkeleton(),
                const SizedBox(height: 12),
                const _DistributionCardSkeleton(rows: 3),
                const SizedBox(height: 12),
                const _DistributionCardSkeleton(rows: 2),
                if (isAdmin) ...[
                  const SizedBox(height: 12),
                  const _DigestCardSkeleton(),
                ],
              ],
            ),
          ),
        ),
        error: (e, _) => withModules(
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Could not load the totals. Pull down to try again.\n$e',
                  style: TextStyle(color: context.colors.textSecondary, fontSize: 14)),
            ),
          ),
          const SizedBox.shrink(),
        ),
        data: (_) => const SizedBox.shrink(), // unreachable: _lastStats would already be set
      );
    }

    final animate = !_hasAnimatedIn;
    _hasAnimatedIn = true;
    Widget maybeStagger(int index, Widget child) =>
        animate ? StaggeredEntrance(index: index, child: child) : child;

    return withModules(
      maybeStagger(
        0,
        _OverviewPanel(
          totalAssets: stats.totalAssets,
          totalValue: stats.totalValue,
          underMaintenance: stats.underMaintenance,
          disposed: stats.disposed,
        ),
      ),
      Column(
      children: [
        maybeStagger(
          1,
          _LifecycleRingCard(
            title: 'Lifecycle Status',
            total: stats.lifecycleDist.values.fold(0, (a, b) => a + b),
            dist: stats.lifecycleDist,
            order: _lifecycleOrder,
            colorOf: _lifecycleDashboardColor,
            labelOf: _lifecycleDashboardLabel,
          ),
        ),
        const SizedBox(height: 12),
        maybeStagger(
          2,
          _DistributionCard(
            title: 'Asset Condition',
            total: stats.totalAssets,
            dist: stats.conditionDist,
            order: _conditionOrder,
            colorOf: (v) => StatusBadge.condition(v).color,
            labelOf: (v) => StatusBadge.condition(v).label,
          ),
        ),
        const SizedBox(height: 12),
        maybeStagger(3, const _AiRecommendationSummaryCard()),
        if (isAdmin) ...[
          const SizedBox(height: 12),
          maybeStagger(4, const _AuditLogDigestCard()),
        ],
      ],
      ),
    );
  }
}

class _AiRecommendationSummaryCard extends ConsumerWidget {
  const _AiRecommendationSummaryCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(aiRecommendationSummaryProvider);

    return summaryAsync.when(
      loading: () => const Shimmer(child: _DistributionCardSkeleton(rows: 3)),
      error: (e, _) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Text('Failed to load AI recommendations: $e',
              style: TextStyle(color: context.colors.textSecondary, fontSize: 14)),
        ),
      ),
      data: (dist) => _DistributionCard(
        title: 'AI Recommendations',
        total: dist.values.fold(0, (a, b) => a + b),
        dist: dist,
        order: _recommendationOrder,
        colorOf: _recColor,
        labelOf: _recLabel,
        emptyMessage: 'No AI recommendations generated yet.',
        totalNoun: 'assets reviewed',
      ),
    );
  }
}

class _AuditLogDigestCard extends ConsumerStatefulWidget {
  const _AuditLogDigestCard();

  @override
  ConsumerState<_AuditLogDigestCard> createState() => _AuditLogDigestCardState();
}

class _AuditLogDigestCardState extends ConsumerState<_AuditLogDigestCard> {
  bool _generating = false;

  Future<void> _generate() async {
    setState(() => _generating = true);
    try {
      await ref.read(auditLogDigestServiceProvider).generate();
      ref.invalidate(auditLogDigestProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString()),
          backgroundColor: Colors.red.shade800,
        ));
      }
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  String _fmtDateTime(String raw) {
    try {
      final dt = DateTime.parse(raw).toLocal();
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return raw;
    }
  }

  @override
  Widget build(BuildContext context) {
    final digestAsync = ref.watch(auditLogDigestProvider);
    final c = context.colors;

    return SectionCard(
      title: 'AI Activity Digest',
      // a worded button, like the web dashboard's "Generate summary"
      trailing: _generating
          ? const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            )
          : TextButton(onPressed: _generate, child: const Text('Generate')),
      child: digestAsync.when(
        loading: () => const Shimmer(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Bone(width: double.infinity, height: 14),
              SizedBox(height: 8),
              Bone(width: double.infinity, height: 14),
              SizedBox(height: 8),
              Bone(width: 160, height: 14),
              SizedBox(height: 12),
              Bone(width: 140, height: 12),
            ],
          ),
        ),
        error: (e, _) => Text(e.toString(), style: TextStyle(color: c.textSecondary, fontSize: 14)),
        data: (digest) {
          if (digest == null) {
            return Text('No digest yet. Tap Generate to write a plain-language summary of recent activity.',
                style: TextStyle(color: c.textSecondary, fontSize: 15, height: 1.45));
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(digest.digest, style: TextStyle(color: c.textSecondary, fontSize: 15, height: 1.5)),
              const SizedBox(height: 10),
              Text(
                'Covers ${digest.coveredEntries} recent entries · generated ${_fmtDateTime(digest.generatedAt)}',
                style: TextStyle(color: c.textTertiary, fontSize: 13),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// The web dashboard's stat cards — label, big number, one-line description — as a 2 × 2 grid.
class _OverviewPanel extends StatelessWidget {
  final int totalAssets;
  final double totalValue;
  final int underMaintenance;
  final int disposed;

  const _OverviewPanel({
    required this.totalAssets,
    required this.totalValue,
    required this.underMaintenance,
    required this.disposed,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget cell(String label, Widget value, String hint) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: c.textTertiary)),
              const SizedBox(height: 4),
              value,
              const SizedBox(height: 2),
              Text(hint, style: TextStyle(fontSize: 13, color: c.textTertiary), maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
        );
    Widget number(double end, String Function(double) fmt) => TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: end),
          duration: AppTheme.motionSlow,
          curve: AppTheme.motionCurve,
          builder: (context, v, _) => FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(fmt(v),
                style: TextStyle(fontSize: 26, height: 1.15, fontWeight: FontWeight.w800, color: c.textPrimary)),
          ),
        );
    String whole(double v) => v.round().toString();

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: cell('ASSETS', number(totalAssets.toDouble(), whole), 'Total registered')),
                VerticalDivider(width: 1, color: c.border),
                Expanded(child: cell('ASSET VALUE', number(totalValue, _fmtMoney), 'Acquisition value')),
              ],
            ),
          ),
          Divider(height: 1, color: c.border),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: cell('MAINTENANCE', number(underMaintenance.toDouble(), whole), 'Under maintenance')),
                VerticalDivider(width: 1, color: c.border),
                Expanded(child: cell('DISPOSED', number(disposed.toDouble(), whole), 'Disposed assets')),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OverviewPanelSkeleton extends StatelessWidget {
  const _OverviewPanelSkeleton();

  @override
  Widget build(BuildContext context) {
    Widget cell() => const Padding(
          padding: EdgeInsets.fromLTRB(16, 14, 12, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Bone(width: 70, height: 11),
              SizedBox(height: 8),
              Bone(width: 80, height: 26),
              SizedBox(height: 6),
              Bone(width: 100, height: 11),
            ],
          ),
        );
    return Card(
      margin: EdgeInsets.zero,
      child: Column(
        children: [
          Row(children: [Expanded(child: cell()), Expanded(child: cell())]),
          Row(children: [Expanded(child: cell()), Expanded(child: cell())]),
        ],
      ),
    );
  }
}

class _DistributionCardSkeleton extends StatelessWidget {
  final int rows;
  const _DistributionCardSkeleton({this.rows = 3});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Bone(width: 120, height: 14),
            const SizedBox(height: 14),
            const Bone(width: double.infinity, height: 8, borderRadius: BorderRadius.all(Radius.circular(4))),
            const SizedBox(height: 14),
            for (var i = 0; i < rows; i++) ...[
              Row(
                children: [
                  const Bone(width: 8, height: 8, borderRadius: BorderRadius.all(Radius.circular(4))),
                  const SizedBox(width: 8),
                  Expanded(child: Bone(width: 80 + (i * 20).toDouble(), height: 12)),
                  const SizedBox(width: 8),
                  const Bone(width: 20, height: 12),
                ],
              ),
              if (i != rows - 1) const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }
}

class _DigestCardSkeleton extends StatelessWidget {
  const _DigestCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Bone(width: 130, height: 12),
            SizedBox(height: 14),
            Bone(width: double.infinity, height: 13),
            SizedBox(height: 8),
            Bone(width: double.infinity, height: 13),
            SizedBox(height: 8),
            Bone(width: 160, height: 13),
          ],
        ),
      ),
    );
  }
}

/// One legend line: dot, label, count, percent — the web dashboard's legend rows.
class _LegendRow extends StatelessWidget {
  final Color color;
  final String label;
  final int count;
  final int pct;
  const _LegendRow({required this.color, required this.label, required this.count, required this.pct});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 10),
          Expanded(child: Text(label, style: TextStyle(color: c.textSecondary, fontSize: 15))),
          Text('$count', style: TextStyle(color: c.textPrimary, fontSize: 15, fontWeight: FontWeight.w700)),
          SizedBox(
            width: 48,
            child: Text('$pct%', textAlign: TextAlign.right, style: TextStyle(color: c.textTertiary, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

class _DistributionCard extends StatelessWidget {
  final String title;
  final int total;
  final Map<String, int> dist;
  final List<String> order;
  final Color Function(String) colorOf;
  final String Function(String) labelOf;
  final String emptyMessage;
  final String totalNoun;

  const _DistributionCard({
    required this.title,
    required this.total,
    required this.dist,
    required this.order,
    required this.colorOf,
    required this.labelOf,
    this.emptyMessage = 'No assets registered yet.',
    this.totalNoun = 'assets',
  });

  @override
  Widget build(BuildContext context) {
    final present = order.where((k) => (dist[k] ?? 0) > 0).toList();

    return SectionCard(
      title: title,
      trailingText: total == 0 ? null : '$total $totalNoun',
      child: total == 0
          ? Text(emptyMessage, style: TextStyle(color: context.colors.textSecondary, fontSize: 15))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: SizedBox(
                    height: 10,
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: 1),
                      duration: AppTheme.motionSlow,
                      curve: AppTheme.motionCurve,
                      builder: (context, progress, child) => FractionallySizedBox(
                        widthFactor: progress,
                        alignment: Alignment.centerLeft,
                        child: child,
                      ),
                      child: Row(
                        children: present
                            .map((k) => Expanded(flex: dist[k] ?? 0, child: Container(color: colorOf(k))))
                            .toList(),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                ...present.map((k) {
                  final count = dist[k] ?? 0;
                  return _LegendRow(
                    color: colorOf(k),
                    label: labelOf(k),
                    count: count,
                    pct: (count * 100 / total).round(),
                  );
                }),
              ],
            ),
    );
  }
}

class _LifecycleRingCard extends StatelessWidget {
  final String title;
  final int total;
  final Map<String, int> dist;
  final List<String> order;
  final Color Function(String) colorOf;
  final String Function(String) labelOf;

  const _LifecycleRingCard({
    required this.title,
    required this.total,
    required this.dist,
    required this.order,
    required this.colorOf,
    required this.labelOf,
  });

  @override
  Widget build(BuildContext context) {
    final present = order.where((k) => (dist[k] ?? 0) > 0).toList();
    final c = context.colors;

    return SectionCard(
      title: title,
      trailingText: total == 0 ? null : '$total total',
      child: total == 0
          ? Text('No assets registered yet.', style: TextStyle(color: c.textSecondary, fontSize: 15))
          : Column(
              children: [
                Center(
                  child: SizedBox(
                    width: 168,
                    height: 168,
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: 1),
                      duration: const Duration(milliseconds: 1100),
                      curve: AppTheme.motionCurve,
                      builder: (context, progress, child) => CustomPaint(
                        painter: _LifecycleRingPainter(
                          segments: present.map((k) => _RingSegment(count: dist[k] ?? 0, color: colorOf(k))).toList(),
                          total: total,
                          trackColor: c.border,
                          progress: progress,
                        ),
                        child: child,
                      ),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('$total',
                                style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.w800, fontSize: 30, height: 1)),
                            const SizedBox(height: 4),
                            Text('ASSETS',
                                style: TextStyle(
                                    color: c.textTertiary, fontSize: 14, fontWeight: FontWeight.w700, letterSpacing: 1)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                ...present.map((k) {
                  final count = dist[k] ?? 0;
                  return _LegendRow(
                    color: colorOf(k),
                    label: labelOf(k),
                    count: count,
                    pct: (count * 100 / total).round(),
                  );
                }),
              ],
            ),
    );
  }
}

class _RingSegment {
  final int count;
  final Color color;
  const _RingSegment({required this.count, required this.color});
}

class _LifecycleRingPainter extends CustomPainter {
  final List<_RingSegment> segments;
  final int total;
  final Color trackColor;
  final double progress;
  static const _strokeWidth = 22.0;
  static const _gapDegrees = 5.0;

  const _LifecycleRingPainter({
    required this.segments,
    required this.total,
    required this.trackColor,
    this.progress = 1.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final rect = Rect.fromCircle(center: center, radius: radius - _strokeWidth / 2);

    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _strokeWidth
      ..color = trackColor.withValues(alpha: 0.4);
    canvas.drawArc(rect, 0, 2 * math.pi, false, trackPaint);

    if (total == 0) return;

    const gapRadians = _gapDegrees * math.pi / 180;
    // Start angles are computed from the un-animated (full) sweep so every
    // segment's position is fixed and correct throughout — only each arc's
    // own length grows with `progress`, so the ring fills in place rather
    // than sliding segments around as they animate.
    var startAngle = -math.pi / 2;

    for (final seg in segments) {
      final fullSweep = (seg.count / total) * 2 * math.pi;
      final animatedSweep = fullSweep * progress;
      final drawnSweep = (animatedSweep - gapRadians).clamp(0.0, animatedSweep);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _strokeWidth
        ..strokeCap = StrokeCap.round
        ..color = seg.color;
      canvas.drawArc(rect, startAngle + gapRadians / 2, drawnSweep, false, paint);
      startAngle += fullSweep;
    }
  }

  @override
  bool shouldRepaint(covariant _LifecycleRingPainter oldDelegate) => true;
}

class _RingCardSkeleton extends StatelessWidget {
  const _RingCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Bone(width: 120, height: 14),
            SizedBox(height: 16),
            Center(child: Bone(width: 176, height: 176, borderRadius: BorderRadius.all(Radius.circular(88)))),
            SizedBox(height: 16),
            Wrap(
              spacing: 14,
              runSpacing: 8,
              children: [
                Bone(width: 90, height: 12),
                Bone(width: 110, height: 12),
                Bone(width: 80, height: 12),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
