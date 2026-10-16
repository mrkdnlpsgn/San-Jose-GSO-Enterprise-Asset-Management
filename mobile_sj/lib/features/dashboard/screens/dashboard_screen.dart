import 'dart:math' as math;
import 'package:flutter/cupertino.dart'
    show CupertinoButton, CupertinoSliverNavigationBar, CupertinoSliverRefreshControl, CupertinoTextThemeData, CupertinoTheme, CupertinoThemeData;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show OverflowBoxFit;
import '../widgets/ios_style.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../auth/provider/auth_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/status_badge.dart';
import '../../../shared/widgets/skeleton.dart';
import '../../../shared/widgets/staggered_entrance.dart';
import '../../../shared/widgets/main_shell.dart';
import '../../../shared/widgets/auto_refresh_ticker.dart';
import '../../../shared/widgets/user_avatar.dart';
import '../../assets/provider/ai_recommendation_provider.dart';
import '../../audit_log/provider/audit_log_digest_provider.dart';
import '../provider/dashboard_provider.dart';
import '../../reports/utils/formatters.dart' show fmtMoney;
import '../widgets/home_header.dart';
import '../widgets/attention_card.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).valueOrNull;
    final isAdmin = user?.isAdmin ?? false;

    void refreshAll() {
      ref.invalidate(dashboardStatsProvider);
      ref.invalidate(aiRecommendationSummaryProvider);
      ref.invalidate(auditLogDigestProvider);
      ref.invalidate(attentionProvider);
    }

    // iOS look on Home: grouped grey background, borderless rounded sections, a large
    // title that collapses into a frosted bar, and iOS pull-to-refresh with rubber-banding.
    return Theme(
      data: Ios.theme(context),
      child: Builder(builder: (context) {
        final c = context.colors;
        final titleFont = TextStyle(fontFamily: AppTheme.fontFamily, color: c.textPrimary, inherit: false);
        return CupertinoTheme(
          data: CupertinoThemeData(
            brightness: context.isLight ? Brightness.light : Brightness.dark,
            primaryColor: Ios.blue,
            textTheme: CupertinoTextThemeData(
              navLargeTitleTextStyle: titleFont.copyWith(fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: -0.9),
              navTitleTextStyle: titleFont.copyWith(fontSize: 17, fontWeight: FontWeight.w600, letterSpacing: -0.3),
            ),
          ),
          child: Scaffold(
            body: AutoRefreshTicker(
              interval: const Duration(seconds: 30),
              onTick: refreshAll,
              child: CustomScrollView(
                // elastic edges, like iOS — and always scrollable so pull-to-refresh works on short pages
                physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                slivers: [
                  CupertinoSliverNavigationBar(
                    largeTitle: const Text('Home'),
                    transitionBetweenRoutes: false, // the app's own page transitions handle this
                    // translucent → the bar frosts (blurs) the content scrolling under it
                    backgroundColor: Ios.groupedBg(context).withValues(alpha: 0.82),
                    border: Border(bottom: BorderSide(color: Ios.separator(context), width: 0.5)),
                    leading: Align(
                      alignment: Alignment.centerLeft,
                      widthFactor: 1,
                      child: Semantics(
                        label: 'San Jose GSO',
                        child: const ClipOval(
                          child: Image(image: AssetImage('assets/images/images.png'), width: 30, height: 30, fit: BoxFit.cover),
                        ),
                      ),
                    ),
                    trailing: Semantics(
                      button: true,
                      label: 'My Account',
                      excludeSemantics: true,
                      child: PressScale(
                        scale: 0.9,
                        child: CupertinoButton(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(36, 36),
                          onPressed: () => context.push('/account'),
                          child: UserAvatar(user: user, size: 32),
                        ),
                      ),
                    ),
                  ),
                  CupertinoSliverRefreshControl(onRefresh: () async => refreshAll()),
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(16, 4, 16, 28 + context.mainShellBottomInset),
                    sliver: SliverList.list(
                      children: [
                        // who is signed in + date/time, then anything waiting on them, then the shortcuts
                        const HomeHeader(),
                        const AttentionCard(),
                        const SizedBox(height: 26),
                        _DashboardStatsSection(modules: _ModuleList(isAdmin: isAdmin)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }),
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
      const _ModuleItem(Icons.build_rounded, 'Maintenance', 'Repairs and maintenance records', '/maintenance', Ios.orange),
      const _ModuleItem(Icons.delete_rounded, 'Disposal', 'Disposal records', '/disposal', Ios.red),
      const _ModuleItem(Icons.swap_horiz_rounded, 'Transfer', 'Move an asset to another office, and transfer requests', '/transfers', Ios.indigo),
      const _ModuleItem(Icons.bar_chart_rounded, 'Reports', 'Inventory reports, RPCPPE, IIRUP and more', '/reports', Ios.green),
      // Asset History is a bottom-bar tab (History), so it isn't repeated here.
      // Reference data, account management and the recycle bin are ADMIN-only —
      // staff work only with their office's assets, maintenance, disposal and reports.
      if (isAdmin) ...const [
        _ModuleItem(Icons.apartment_rounded, 'Offices', 'Offices and their head users', '/offices', Ios.blue),
        _ModuleItem(Icons.category_rounded, 'Categories', 'Asset categories', '/categories', Ios.purple),
        _ModuleItem(Icons.badge_rounded, 'Personnel', 'Assign each account its office', '/personnel', Ios.teal),
        _ModuleItem(Icons.people_rounded, 'Accounts', 'Create and manage user accounts', '/accounts', Ios.gray),
        _ModuleItem(Icons.restore_from_trash_rounded, 'Recycle Bin', 'Restore deleted records', '/recycle-bin', Ios.pink),
      ],
    ];
    // iOS home-screen style: colourful rounded-square "app icons" with the name underneath, in
    // one sideways-scrolling row. Sized so ~4½ fit on a phone: the half-cut tile at the edge is
    // the cue that there's more to swipe to. The row runs to the screen edges (past Home's
    // 16px padding) so tiles scroll off-screen instead of being clipped mid-page.
    const gutter = 16.0;
    return LayoutBuilder(builder: (context, box) {
      final fullWidth = box.maxWidth + gutter * 2;
      final visible = box.maxWidth >= 560 ? 6.5 : 4.5;
      final cellWidth = (box.maxWidth / visible).clamp(76.0, 110.0);
      return OverflowBox(
        minWidth: fullWidth,
        maxWidth: fullWidth,
        // inside Home's vertical list the height is unbounded — take it from the row
        fit: OverflowBoxFit.deferToChild,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: gutter - 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final item in items)
                SizedBox(width: cellWidth, child: _ModuleShortcut(item: item)),
            ],
          ),
        ),
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
    final label = TextStyle(fontSize: 13.5, height: 1.2, fontWeight: FontWeight.w500, letterSpacing: -0.1, color: c.textPrimary);
    return Semantics(
      button: true,
      label: '${item.title}. ${item.subtitle}',
      excludeSemantics: true,
      child: PressScale(
        scale: 0.9,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => context.push(item.route),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
            child: Column(
              children: [
                // iOS app icon: vertical system-colour gradient on a continuous-corner square
                Container(
                  width: 62,
                  height: 62,
                  decoration: ShapeDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color.lerp(item.color, Colors.white, 0.18)!, item.color],
                    ),
                    shape: ContinuousRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    shadows: [
                      BoxShadow(color: item.color.withValues(alpha: 0.28), blurRadius: 10, offset: const Offset(0, 4)),
                    ],
                  ),
                  child: Icon(item.icon, size: 30, color: Colors.white),
                ),
                const SizedBox(height: 8),
                // two-word names wrap onto two lines; a single long word ("Maintenance") shrinks a
                // little to fit instead of being split mid-word at the Large text size
                if (item.title.contains(' '))
                  Text(item.title, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: label)
                else
                  FittedBox(fit: BoxFit.scaleDown, child: Text(item.title, maxLines: 1, style: label)),
              ],
            ),
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
  final Color color;
  const _ModuleItem(this.icon, this.title, this.subtitle, this.route, this.color);
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
    final isAdmin = ref.watch(authProvider).valueOrNull?.isAdmin ?? false;

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
            const SizedBox(height: 28),
            const IosSectionHeader('Overview'),
            overview,
            const SizedBox(height: 28),
            const IosSectionHeader('Summary'),
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
            icon: Icons.verified_rounded,
            accent: Ios.green,
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
        icon: Icons.lightbulb_rounded,
        accent: Ios.purple,
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

    return _SummaryCard(
      icon: Icons.auto_awesome_rounded,
      accent: Ios.indigo,
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
              Text(digest.digest, style: TextStyle(color: c.textPrimary, fontSize: 16, height: 1.5, letterSpacing: -0.2)),
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
    // Counts up once on first load; plain numbers, no icons — an official summary, not a promo.
    // Reduce Motion: the final figure straight away (a rolling peso amount is hard to read).
    final still = context.prefersReducedMotion;
    Widget counter(double end, String Function(double) fmt, TextStyle style) => TweenAnimationBuilder<double>(
          tween: Tween(begin: still ? end : 0, end: end),
          duration: still ? Duration.zero : AppTheme.motionSlow,
          curve: AppTheme.motionCurve,
          builder: (context, v, _) => FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(fmt(v), maxLines: 1, style: style),
          ),
        );

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Headline: the full peso amount (not "₱12.3M") — officials read and quote the exact figure.
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Total Asset Value',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: -0.2, color: c.textSecondary)),
                const SizedBox(height: 2),
                // large numerals get negative tracking, as iOS sets big text
                counter(totalValue, (v) => fmtMoney(v),
                    TextStyle(fontSize: 32, height: 1.15, fontWeight: FontWeight.w700, letterSpacing: -1, color: c.textPrimary)),
                const SizedBox(height: 4),
                Text(
                  'Acquisition cost of all registered assets',
                  style: TextStyle(fontSize: 15, color: c.textSecondary),
                ),
              ],
            ),
          ),
          // One full-width row per count, so labels never wrap — not three squeezed columns.
          const Divider(height: 1),
          _StatRow(
            label: 'Registered assets',
            value: counter(totalAssets.toDouble(), (v) => _fmtCount(v.round()), _StatRow.numberStyle(c)),
            icon: Icons.inventory_2_rounded,
            dot: Ios.green,
            semantics: '${_fmtCount(totalAssets)} registered assets. Open Assets.',
            onTap: () => context.go('/assets'), // bottom-bar tab
          ),
          const Divider(height: 1, indent: 60),
          _StatRow(
            label: 'In maintenance',
            value: counter(underMaintenance.toDouble(), (v) => _fmtCount(v.round()), _StatRow.numberStyle(c)),
            icon: Icons.build_rounded,
            dot: Ios.orange,
            semantics: '${_fmtCount(underMaintenance)} in maintenance. Open Maintenance.',
            onTap: () => context.push('/maintenance'),
          ),
          const Divider(height: 1, indent: 60),
          _StatRow(
            label: 'Disposed',
            value: counter(disposed.toDouble(), (v) => _fmtCount(v.round()), _StatRow.numberStyle(c)),
            icon: Icons.delete_rounded,
            dot: Ios.red,
            semantics: '${_fmtCount(disposed)} disposed. Open Disposal.',
            onTap: () => context.push('/disposal'),
          ),
        ],
      ),
    );
  }
}

/// 2024 -> "2,024"
String _fmtCount(int n) {
  final s = n.abs().toString();
  final buf = StringBuffer(n < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return buf.toString();
}

/// One tappable count under the headline: a coloured dot (the same colour as that status's
/// badges elsewhere) and the label on the left, the number on the right, then a chevron.
class _StatRow extends StatelessWidget {
  final String label;
  final Widget value;
  final IconData icon;
  final Color dot;
  final String semantics;
  final VoidCallback onTap;

  const _StatRow({
    required this.label,
    required this.icon,
    required this.value,
    required this.dot,
    required this.semantics,
    required this.onTap,
  });

  static TextStyle numberStyle(AppColors c) =>
      TextStyle(fontSize: 17, height: 1.2, fontWeight: FontWeight.w500, letterSpacing: -0.2, color: c.textSecondary);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: semantics,
      excludeSemantics: true,
      // iOS Settings row: system-colour icon tile, label, value in grey, thin chevron
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 54),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 14, 10),
            child: Row(
              children: [
                IosIconTile(icon: icon, color: dot),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(label,
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w400, letterSpacing: -0.3, color: c.textPrimary)),
                ),
                const SizedBox(width: 12),
                // the counter's FittedBox needs a bounded width to scale into
                ConstrainedBox(constraints: const BoxConstraints(maxWidth: 120), child: value),
                const SizedBox(width: 8),
                const IosChevron(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OverviewPanelSkeleton extends StatelessWidget {
  const _OverviewPanelSkeleton();

  @override
  Widget build(BuildContext context) {
    Widget row() => const Padding(
          padding: EdgeInsets.fromLTRB(18, 18, 18, 18),
          child: Row(
            children: [
              Bone(width: 10, height: 10),
              SizedBox(width: 12),
              Bone(width: 130, height: 14),
              Spacer(),
              Bone(width: 48, height: 18),
            ],
          ),
        );
    return Card(
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(18, 16, 18, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Bone(width: 130, height: 12),
                SizedBox(height: 8),
                Bone(width: 210, height: 32),
                SizedBox(height: 8),
                Bone(width: 230, height: 13),
              ],
            ),
          ),
          row(),
          row(),
          row(),
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

/// Health-app style summary card: a small tinted icon + title at the top (no divider under
/// it), an optional trailing action, an optional big headline number, then the content.
class _SummaryCard extends StatelessWidget {
  final IconData icon;
  final Color accent;
  final String title;
  final Widget? trailing;
  final String? headline;
  final String? headlineUnit;
  final Widget child;

  const _SummaryCard({
    required this.icon,
    required this.accent,
    required this.title,
    required this.child,
    this.trailing,
    this.headline,
    this.headlineUnit,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, trailing != null ? 6 : 14, trailing != null ? 6 : 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: accent),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(title,
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: -0.2, color: accent)),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            Padding(
              padding: EdgeInsets.only(right: trailing != null ? 10 : 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (headline != null) ...[
                    const SizedBox(height: 6),
                    Text.rich(TextSpan(children: [
                      TextSpan(
                        text: headline,
                        style: TextStyle(
                            fontSize: 30, height: 1.1, fontWeight: FontWeight.w700, letterSpacing: -0.9, color: c.textPrimary),
                      ),
                      if (headlineUnit != null)
                        TextSpan(
                          text: ' $headlineUnit',
                          style:
                              TextStyle(fontSize: 17, fontWeight: FontWeight.w600, letterSpacing: -0.3, color: c.textTertiary),
                        ),
                    ])),
                  ],
                  const SizedBox(height: 12),
                  child,
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The legend as an inset iOS list: dot, label, then the count and its share in grey, with
/// hairlines that start at the label (not the card edge).
class _LegendList extends StatelessWidget {
  final List<String> keys;
  final Map<String, int> dist;
  final int total;
  final Color Function(String) colorOf;
  final String Function(String) labelOf;

  const _LegendList({
    required this.keys,
    required this.dist,
    required this.total,
    required this.colorOf,
    required this.labelOf,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      children: [
        for (var i = 0; i < keys.length; i++) ...[
          if (i > 0) const Divider(height: 1, indent: 22),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 11),
            child: Row(
              children: [
                Container(
                    width: 10, height: 10, decoration: BoxDecoration(color: colorOf(keys[i]), shape: BoxShape.circle)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(labelOf(keys[i]), style: TextStyle(fontSize: 16, letterSpacing: -0.3, color: c.textPrimary)),
                ),
                Text(_fmtCount(dist[keys[i]] ?? 0),
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: -0.2, color: c.textPrimary)),
                SizedBox(
                  width: 50,
                  child: Text('${((dist[keys[i]] ?? 0) * 100 / total).round()}%',
                      textAlign: TextAlign.right, style: TextStyle(fontSize: 15, color: c.textTertiary)),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _DistributionCard extends StatelessWidget {
  final IconData icon;
  final Color accent;
  final String title;
  final int total;
  final Map<String, int> dist;
  final List<String> order;
  final Color Function(String) colorOf;
  final String Function(String) labelOf;
  final String emptyMessage;
  final String totalNoun;

  const _DistributionCard({
    required this.icon,
    required this.accent,
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
    final c = context.colors;

    return _SummaryCard(
      icon: icon,
      accent: accent,
      title: title,
      headline: total == 0 ? null : _fmtCount(total),
      headlineUnit: total == 0 ? null : totalNoun,
      child: total == 0
          ? Text(emptyMessage, style: TextStyle(color: c.textSecondary, fontSize: 15))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // capsule bar: fully rounded ends, hairline gaps between the parts
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: SizedBox(
                    height: 12,
                    child: TweenAnimationBuilder<double>(
                      // Reduce Motion: drawn at full width, no grow
                      tween: Tween(begin: context.prefersReducedMotion ? 1 : 0, end: 1),
                      duration: context.prefersReducedMotion ? Duration.zero : AppTheme.motionSlow,
                      curve: AppTheme.motionCurve,
                      builder: (context, progress, child) => FractionallySizedBox(
                        widthFactor: progress,
                        alignment: Alignment.centerLeft,
                        child: child,
                      ),
                      child: Row(
                        children: [
                          for (var i = 0; i < present.length; i++) ...[
                            if (i > 0) Container(width: 2, color: c.surface),
                            Expanded(flex: dist[present[i]] ?? 0, child: Container(color: colorOf(present[i]))),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                _LegendList(keys: present, dist: dist, total: total, colorOf: colorOf, labelOf: labelOf),
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

    return _SummaryCard(
      icon: Icons.donut_large_rounded,
      accent: Ios.blue,
      title: title,
      child: total == 0
          ? Text('No assets registered yet.', style: TextStyle(color: c.textSecondary, fontSize: 15))
          : Column(
              children: [
                const SizedBox(height: 4),
                Center(
                  child: SizedBox(
                    width: 176,
                    height: 176,
                    child: TweenAnimationBuilder<double>(
                      // fills once in 600ms (was 1.1s); Reduce Motion: drawn complete, no sweep
                      tween: Tween(begin: context.prefersReducedMotion ? 1 : 0, end: 1),
                      duration: context.prefersReducedMotion ? Duration.zero : const Duration(milliseconds: 600),
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
                            Text(_fmtCount(total),
                                style: TextStyle(
                                    color: c.textPrimary,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 30,
                                    height: 1,
                                    letterSpacing: -0.9)),
                            const SizedBox(height: 4),
                            Text('assets', style: TextStyle(color: c.textTertiary, fontSize: 15, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                _LegendList(keys: present, dist: dist, total: total, colorOf: colorOf, labelOf: labelOf),
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
