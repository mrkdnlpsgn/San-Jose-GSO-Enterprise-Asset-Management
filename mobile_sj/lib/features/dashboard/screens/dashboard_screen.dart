import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../auth/provider/auth_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/status_badge.dart';
import '../../../shared/widgets/skeleton.dart';
import '../../../shared/widgets/staggered_entrance.dart';
import '../../../shared/widgets/main_shell.dart';
import '../../../shared/widgets/auto_refresh_ticker.dart';
import '../../../shared/widgets/logout_dialog.dart';
import '../../assets/provider/ai_recommendation_provider.dart';
import '../../audit_log/provider/audit_log_digest_provider.dart';
import '../provider/dashboard_provider.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).value;
    final isAdmin = user?.isAdmin ?? false;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: AppTheme.brand.withValues(alpha: 0.3), width: 1.5),
              ),
              child: const ClipOval(
                child: Image(image: AssetImage('assets/images/images.png'), fit: BoxFit.cover),
              ),
            ),
            const SizedBox(width: 10),
            const Text('Dashboard'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            tooltip: 'Logout',
            onPressed: () async {
              final confirmed = await showLogoutDialog(context);
              if (confirmed == true) ref.read(authProvider.notifier).logout();
            },
          ),
        ],
      ),
      body: AutoRefreshTicker(
        interval: const Duration(seconds: 30),
        onTick: () {
          ref.invalidate(dashboardStatsProvider);
          ref.invalidate(aiRecommendationSummaryProvider);
          ref.invalidate(auditLogDigestProvider);
        },
        child: RefreshIndicator(
        color: AppTheme.brand,
        onRefresh: () async {
          ref.invalidate(dashboardStatsProvider);
          ref.invalidate(aiRecommendationSummaryProvider);
          ref.invalidate(auditLogDigestProvider);
        },
        child: ListView(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + context.mainShellBottomInset),
        children: [
          _sectionLabel(context, 'OVERVIEW'),
          const SizedBox(height: 12),
          const _DashboardStatsSection(),

          const SizedBox(height: 24),

          _sectionLabel(context, 'MODULES'),
          const SizedBox(height: 12),

          StaggeredEntrance(
            index: 0,
            child: _NavCard(
              icon: Icons.build_outlined,
              title: 'Maintenance',
              subtitle: 'View maintenance ledger records',
              color: AppTheme.statusMaintenance,
              onTap: () => context.push('/maintenance'),
            ),
          ),
          const SizedBox(height: 10),
          StaggeredEntrance(
            index: 1,
            child: _NavCard(
              icon: Icons.delete_outline_rounded,
              title: 'Disposal',
              subtitle: 'View disposal ledger records',
              color: AppTheme.statusDisposed,
              onTap: () => context.push('/disposal'),
            ),
          ),
          const SizedBox(height: 10),
          StaggeredEntrance(
            index: 2,
            child: _NavCard(
              icon: Icons.summarize_outlined,
              title: 'Reports',
              subtitle: 'Generate and export inventory reports, including COA RPCPPE/IIRUP',
              color: AppTheme.brandDark,
              onTap: () => context.push('/reports'),
            ),
          ),
          const SizedBox(height: 10),
          StaggeredEntrance(
            index: 3,
            child: _NavCard(
              icon: Icons.category_outlined,
              title: 'Categories',
              subtitle: 'Manage asset categories',
              color: AppTheme.brand,
              onTap: () => context.push('/categories'),
            ),
          ),
          const SizedBox(height: 10),
          StaggeredEntrance(
            index: 4,
            child: _NavCard(
              icon: Icons.apartment_outlined,
              title: 'Offices',
              subtitle: 'Manage offices and their head users',
              color: AppTheme.brand,
              onTap: () => context.push('/offices'),
            ),
          ),
          if (isAdmin) ...[
            const SizedBox(height: 10),
            StaggeredEntrance(
              index: 5,
              child: _NavCard(
                icon: Icons.manage_accounts_outlined,
                title: 'Manage Accounts',
                subtitle: 'Create and manage user accounts',
                color: AppTheme.statusAssigned,
                onTap: () => context.push('/accounts'),
              ),
            ),
          ],
          const SizedBox(height: 10),
          StaggeredEntrance(
            index: 6,
            child: _NavCard(
              icon: Icons.restore_from_trash_outlined,
              title: 'Recycle Bin',
              subtitle: 'View and restore deleted assets, maintenance, and disposal records',
              color: AppTheme.statusRegistered,
              onTap: () => context.push('/recycle-bin'),
            ),
          ),
        ],
        ),
      ),
      ),
    );
  }

  Widget _sectionLabel(BuildContext context, String label) => Text(
        label,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: context.colors.textSecondary,
              fontWeight: FontWeight.w600,
              letterSpacing: 1,
            ),
      );
}

class _NavCard extends StatefulWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _NavCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  State<_NavCard> createState() => _NavCardState();
}

class _NavCardState extends State<_NavCard> {
  bool _pressed = false;

  void _setPressed(bool v) => setState(() => _pressed = v);

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: _pressed ? 0.98 : 1.0,
      duration: AppTheme.motionFast,
      curve: AppTheme.motionCurve,
      child: Card(
        child: InkWell(
          onTap: widget.onTap,
          onTapDown: (_) => _setPressed(true),
          onTapUp: (_) => _setPressed(false),
          onTapCancel: () => _setPressed(false),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: widget.color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(widget.icon, color: widget.color, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.title,
                          style: TextStyle(color: context.colors.textPrimary, fontWeight: FontWeight.w600, fontSize: 15)),
                      const SizedBox(height: 2),
                      Text(widget.subtitle, style: TextStyle(color: context.colors.textTertiary, fontSize: 13)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: context.colors.textSecondary),
              ],
            ),
          ),
        ),
      ),
    );
  }
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
      'MONITOR' => AppTheme.statusAssigned,
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
  const _DashboardStatsSection();

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

    if (stats == null) {
      return statsAsync.when(
        loading: () => Shimmer(
          child: Column(
            children: [
              const _OverviewPanelSkeleton(),
              const SizedBox(height: 10),
              const _RingCardSkeleton(),
              const SizedBox(height: 10),
              const _DistributionCardSkeleton(rows: 3),
              const SizedBox(height: 10),
              const _DistributionCardSkeleton(rows: 2),
              if (isAdmin) ...[
                const SizedBox(height: 10),
                const _DigestCardSkeleton(),
              ],
            ],
          ),
        ),
        error: (e, _) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Text('Failed to load stats: $e', style: TextStyle(color: context.colors.textTertiary, fontSize: 13)),
        ),
        data: (_) => const SizedBox.shrink(), // unreachable: _lastStats would already be set
      );
    }

    final animate = !_hasAnimatedIn;
    _hasAnimatedIn = true;
    Widget maybeStagger(int index, Widget child) =>
        animate ? StaggeredEntrance(index: index, child: child) : child;

    return Column(
      children: [
        maybeStagger(
          0,
          _OverviewPanel(
            totalAssets: stats.totalAssets,
            totalValue: stats.totalValue,
            underMaintenance: stats.underMaintenance,
            disposed: stats.disposed,
          ),
        ),
        const SizedBox(height: 10),
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
        const SizedBox(height: 10),
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
        const SizedBox(height: 10),
        maybeStagger(3, const _AiRecommendationSummaryCard()),
        if (isAdmin) ...[
          const SizedBox(height: 10),
          maybeStagger(4, const _AuditLogDigestCard()),
        ],
      ],
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
              style: TextStyle(color: context.colors.textSecondary, fontSize: 12)),
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
      final dt = DateTime.parse(raw);
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return raw;
    }
  }

  @override
  Widget build(BuildContext context) {
    final digestAsync = ref.watch(auditLogDigestProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.auto_awesome_rounded, size: 16, color: AppTheme.brand),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('AI ACTIVITY DIGEST',
                      style: TextStyle(color: context.colors.textTertiary, fontSize: 12,
                          fontWeight: FontWeight.w600, letterSpacing: 0.8)),
                ),
                _generating
                    ? const SizedBox(width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.brand))
                    : IconButton(
                        icon: Icon(Icons.refresh_rounded, size: 18, color: context.colors.textTertiary),
                        tooltip: 'Generate digest',
                        onPressed: _generate,
                        visualDensity: VisualDensity.compact,
                        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                      ),
              ],
            ),
            const SizedBox(height: 12),
            digestAsync.when(
              loading: () => const Shimmer(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Bone(width: double.infinity, height: 13),
                    SizedBox(height: 8),
                    Bone(width: double.infinity, height: 13),
                    SizedBox(height: 8),
                    Bone(width: 160, height: 13),
                    SizedBox(height: 12),
                    Bone(width: 140, height: 11),
                  ],
                ),
              ),
              error: (e, _) => Text(e.toString(), style: TextStyle(color: context.colors.textSecondary, fontSize: 12)),
              data: (digest) {
                if (digest == null) {
                  return Text('No digest yet. Tap refresh to generate one.',
                      style: TextStyle(color: context.colors.textSecondary, fontSize: 13));
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(digest.digest, style: TextStyle(color: context.colors.textSecondary, fontSize: 13, height: 1.5)),
                    const SizedBox(height: 10),
                    Text(
                      'Covers ${digest.coveredEntries} recent entries · generated ${_fmtDateTime(digest.generatedAt)}',
                      style: TextStyle(color: context.colors.textSecondary, fontSize: 11),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

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
    final width = MediaQuery.sizeOf(context).width;
    final isMediumOrLarger = width >= 600;
    final heroFontSize = isMediumOrLarger ? 52.0 : 40.0;
    final secondaryFontSize = isMediumOrLarger ? 30.0 : 24.0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.brandButton,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('ASSET OVERVIEW',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1)),
              const Spacer(),
              Icon(Icons.inventory_2_rounded, color: Colors.white.withValues(alpha: 0.5), size: 18),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: totalAssets.toDouble()),
                    duration: AppTheme.motionSlow,
                    curve: AppTheme.motionCurve,
                    builder: (context, value, _) => Text(value.round().toString(),
                        style: TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w800, fontSize: heroFontSize, height: 1)),
                  ),
                  const SizedBox(height: 4),
                  Text('Total Assets', style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 13)),
                ],
              ),
              const SizedBox(width: 20),
              Container(width: 1, height: 40, color: Colors.white.withValues(alpha: 0.2)),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: totalValue),
                      duration: AppTheme.motionSlow,
                      curve: AppTheme.motionCurve,
                      builder: (context, value, _) => Text(_fmtMoney(value),
                          style: TextStyle(
                              color: Colors.white, fontWeight: FontWeight.w700, fontSize: secondaryFontSize, height: 1),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ),
                    const SizedBox(height: 4),
                    Text('Asset Value', style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 13)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Container(height: 1, color: Colors.white.withValues(alpha: 0.15)),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _MiniStat(icon: Icons.build_rounded, label: 'Under Maintenance', value: underMaintenance),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MiniStat(icon: Icons.delete_rounded, label: 'Disposed', value: disposed),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final IconData icon;
  final String label;
  final int value;

  const _MiniStat({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white.withValues(alpha: 0.85), size: 16),
          const SizedBox(width: 8),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: value.toDouble()),
            duration: AppTheme.motionSlow,
            curve: AppTheme.motionCurve,
            builder: (context, v, _) => Text(v.round().toString(),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(label,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 11),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
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
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Bone(width: 110, height: 12),
            SizedBox(height: 18),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Bone(width: 70, height: 40),
                SizedBox(width: 20),
                Bone(width: 90, height: 26),
              ],
            ),
            SizedBox(height: 18),
            Bone(width: double.infinity, height: 1),
            SizedBox(height: 14),
            Row(
              children: [
                Expanded(child: Bone(width: double.infinity, height: 36, borderRadius: BorderRadius.all(Radius.circular(10)))),
                SizedBox(width: 10),
                Expanded(child: Bone(width: double.infinity, height: 36, borderRadius: BorderRadius.all(Radius.circular(10)))),
              ],
            ),
          ],
        ),
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

class _DistributionCard extends StatelessWidget {
  final String title;
  final int total;
  final Map<String, int> dist;
  final List<String> order;
  final Color Function(String) colorOf;
  final String Function(String) labelOf;
  final String emptyMessage;

  const _DistributionCard({
    required this.title,
    required this.total,
    required this.dist,
    required this.order,
    required this.colorOf,
    required this.labelOf,
    this.emptyMessage = 'No assets registered yet.',
  });

  @override
  Widget build(BuildContext context) {
    final present = order.where((k) => (dist[k] ?? 0) > 0).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: TextStyle(color: context.colors.textPrimary, fontWeight: FontWeight.w600, fontSize: 14)),
            const SizedBox(height: 12),
            if (total == 0)
              Text(emptyMessage, style: TextStyle(color: context.colors.textSecondary, fontSize: 12))
            else ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: SizedBox(
                  height: 8,
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
                      children: present.map((k) {
                        final count = dist[k] ?? 0;
                        return Expanded(
                          flex: count,
                          child: Container(color: colorOf(k)),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              ...present.map((k) {
                final count = dist[k] ?? 0;
                final pct = total == 0 ? 0 : (count * 100 / total).round();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Container(
                        width: 8, height: 8,
                        decoration: BoxDecoration(color: colorOf(k), shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(labelOf(k), style: TextStyle(color: context.colors.textTertiary, fontSize: 12)),
                      ),
                      Text('$count', style: TextStyle(color: context.colors.textPrimary, fontSize: 12, fontWeight: FontWeight.w600)),
                      const SizedBox(width: 6),
                      SizedBox(
                        width: 32,
                        child: Text('$pct%', textAlign: TextAlign.right,
                            style: TextStyle(color: context.colors.textSecondary, fontSize: 11)),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ],
        ),
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

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: TextStyle(color: context.colors.textPrimary, fontWeight: FontWeight.w600, fontSize: 14)),
            if (total == 0)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text('No assets registered yet.', style: TextStyle(color: context.colors.textSecondary, fontSize: 12)),
              )
            else ...[
              const SizedBox(height: 16),
              Center(
                child: SizedBox(
                  width: 176,
                  height: 176,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: 1),
                    duration: const Duration(milliseconds: 1100),
                    curve: AppTheme.motionCurve,
                    builder: (context, progress, child) => CustomPaint(
                      painter: _LifecycleRingPainter(
                        segments: present.map((k) => _RingSegment(count: dist[k] ?? 0, color: colorOf(k))).toList(),
                        total: total,
                        trackColor: context.colors.border,
                        progress: progress,
                      ),
                      child: child,
                    ),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('$total',
                              style: TextStyle(
                                  color: context.colors.textPrimary, fontWeight: FontWeight.w800, fontSize: 28, height: 1)),
                          const SizedBox(height: 2),
                          Text('ASSETS',
                              style: TextStyle(
                                  color: context.colors.textTertiary,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 1)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 14,
                runSpacing: 8,
                children: present.map((k) {
                  final count = dist[k] ?? 0;
                  final pct = total == 0 ? 0 : (count * 100 / total).round();
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8, height: 8,
                        decoration: BoxDecoration(color: colorOf(k), shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 6),
                      Text('${labelOf(k)} · $count ($pct%)',
                          style: TextStyle(color: context.colors.textTertiary, fontSize: 12)),
                    ],
                  );
                }).toList(),
              ),
            ],
          ],
        ),
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
