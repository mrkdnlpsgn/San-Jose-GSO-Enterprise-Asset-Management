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
import '../provider/dashboard_provider.dart';
import '../provider/planning_provider.dart';
import '../../reports/utils/formatters.dart' show fmtMoney;
import '../widgets/home_header.dart';
import '../../notifications/provider/notifications_provider.dart';
import '../../notifications/widgets/notification_bell.dart';
import '../widgets/budget_planning_card.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).valueOrNull;
    final isAdmin = user?.isAdmin ?? false;
    // Budget & Planning covers the entire inventory: admins and Admin-Staff
    final canPlan = user?.seesAllAssets ?? false;

    void refreshAll() {
      ref.invalidate(dashboardStatsProvider);
      if (canPlan) ref.invalidate(planningProvider);
      ref.invalidate(notificationsProvider);
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
                // elastic edges, like iOS - and always scrollable so pull-to-refresh works on short pages
                physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                slivers: [
                  CupertinoSliverNavigationBar(
                    // centred like every other screen's title; the small one shows once it's scrolled away
                    largeTitle: const SizedBox(width: double.infinity, child: Text('Home', textAlign: TextAlign.center)),
                    middle: const Text('Home'),
                    alwaysShowMiddle: false,
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
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const NotificationBell(),
                        const SizedBox(width: 4),
                        Semantics(
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
                      ],
                    ),
                  ),
                  CupertinoSliverRefreshControl(onRefresh: () async => refreshAll()),
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(16, 4, 16, 28 + context.mainShellBottomInset),
                    sliver: SliverList.list(
                      children: [
                        // who is signed in + date/time, then the shortcuts; anything waiting on them is
                        // behind the bell in the top bar
                        const HomeHeader(),
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
      // Reference data, account management and the recycle bin are ADMIN-only -
      // staff work only with their office's assets, maintenance, disposal and reports.
      if (isAdmin) ...const [
        _ModuleItem(Icons.apartment_rounded, 'Offices', 'Offices', '/offices', Ios.blue),
        _ModuleItem(Icons.category_rounded, 'Categories', 'Asset categories', '/categories', Ios.purple),
        _ModuleItem(Icons.badge_rounded, 'Personnel', 'Assign each account its office', '/personnel', Ios.teal),
        _ModuleItem(Icons.people_rounded, 'Accounts', 'Create and manage user accounts', '/accounts', Ios.gray),
        _ModuleItem(Icons.restore_from_trash_rounded, 'Recovery', 'Restore deleted records', '/recycle-bin', Ios.pink),
        _ModuleItem(Icons.history_edu_rounded, 'Audit Logs', 'Who did what, and the log archive', '/audit-logs', Color(0xFFA2845E)),
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
        // inside Home's vertical list the height is unbounded - take it from the row
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

const _conditionOrder = ['NEW', 'GOOD', 'SERVICEABLE', 'REPAIRABLE', 'UNSERVICEABLE'];

// Same as the web dashboard: the 6 largest offices and categories.
const _topGroups = 6;

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
    // Admin-Staff sees the entire inventory, so its Home is the admin's (offices chart, Budget &
    // Planning); only the module shortcuts to admin pages stay admin-only.
    final adminHome = ref.watch(authProvider).valueOrNull?.seesAllAssets ?? false;

    if (statsAsync.hasValue) _lastStats = statsAsync.value;
    // Keep rendering the last snapshot while a refresh is in flight instead
    // of dropping back to the skeleton - a pull-to-refresh would otherwise
    // tear down and recreate every card, replaying the stagger entrance and
    // restarting the count-up animations from zero on data the user is
    // already looking at.
    final stats = _lastStats;

    // The module list doesn't depend on the stats - show it straight away, even while loading.
    Widget withModules(Widget overview, Widget charts) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // shortcuts first, as on eGovPH's home screen - getting around comes before the numbers
            widget.modules,
            const SizedBox(height: 28),
            const IosSectionHeader('Overview'),
            overview,
            // budget planning covers the entire inventory (admins and Admin-Staff);
            // staff Home stays on their own work
            if (adminHome) ...[
              const SizedBox(height: 28),
              const IosSectionHeader('Budget & Planning'),
              const BudgetPlanningCard(),
            ],
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
                const _DistributionCardSkeleton(rows: 3),
                if (adminHome) ...[
                  const SizedBox(height: 12),
                  const _DistributionCardSkeleton(rows: 4),
                ],
                const SizedBox(height: 12),
                const _DistributionCardSkeleton(rows: 4),
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

    final needAction = (stats.conditionDist['REPAIRABLE'] ?? 0) + (stats.conditionDist['UNSERVICEABLE'] ?? 0);
    final officeCount = stats.offices.length;
    final cards = <Widget>[
      _DistributionCard(
        icon: Icons.verified_rounded,
        accent: Ios.green,
        title: 'Asset Condition',
        total: stats.inUse,
        dist: stats.conditionDist,
        order: _conditionOrder,
        colorOf: (v) => StatusBadge.condition(v).color,
        labelOf: (v) => StatusBadge.condition(v).label,
        footer: '${_fmtCount(needAction)} ${needAction == 1 ? 'asset needs' : 'assets need'} repair or disposal'
            ' · ${_fmtPct(needAction, stats.inUse)}',
      ),
      // offices are an admin view - staff only ever see their own office
      if (adminHome)
        _BarListCard(
          icon: Icons.apartment_rounded,
          accent: Ios.blue,
          title: 'Assets by Office',
          caption: officeCount > _topGroups ? 'Top $_topGroups of $officeCount offices' : '$officeCount offices',
          groups: stats.offices.take(_topGroups).toList(),
          barColor: Ios.blue,
          emptyMessage: 'No office data available.',
        ),
      _BarListCard(
        icon: Icons.category_rounded,
        accent: Ios.purple,
        title: 'Assets by Category',
        caption: '${_fmtCount(stats.inUse)} assets',
        groups: stats.categories.take(_topGroups).toList(),
        barColor: AppTheme.brand,
        shareOf: stats.inUse,
        emptyMessage: 'No assets yet.',
      ),
    ];

    return withModules(
      maybeStagger(
        0,
        _OverviewPanel(
          inUse: stats.inUse,
          totalValue: stats.totalValue,
          newThisMonth: stats.newThisMonth,
          underRepair: stats.underRepair,
          forDisposal: stats.forDisposal,
        ),
      ),
      Column(
        children: [
          for (var i = 0; i < cards.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            maybeStagger(i + 1, cards[i]),
          ],
        ],
      ),
    );
  }
}

/// The web dashboard's stat strip - Asset Value as the headline, then Assets in use, Under
/// Repair and For Disposal as tappable rows.
class _OverviewPanel extends StatelessWidget {
  final int inUse;
  final double totalValue;
  final int newThisMonth;
  final int underRepair;
  final int forDisposal;

  const _OverviewPanel({
    required this.inUse,
    required this.totalValue,
    required this.newThisMonth,
    required this.underRepair,
    required this.forDisposal,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // Counts up once on first load; plain numbers, no icons - an official summary, not a promo.
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
          // Headline: the full peso amount (not "₱12.3M") - officials read and quote the exact figure.
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Asset Value',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: -0.2, color: c.textSecondary)),
                const SizedBox(height: 2),
                // large numerals get negative tracking, as iOS sets big text
                counter(totalValue, (v) => fmtMoney(v),
                    TextStyle(fontSize: 32, height: 1.15, fontWeight: FontWeight.w700, letterSpacing: -1, color: c.textPrimary)),
                const SizedBox(height: 4),
                Text(
                  'Acquisition cost of assets in use',
                  style: TextStyle(fontSize: 15, color: c.textSecondary),
                ),
              ],
            ),
          ),
          // One full-width row per count, so labels never wrap - not three squeezed columns.
          const Divider(height: 1),
          _StatRow(
            label: 'Assets in use',
            badge: newThisMonth > 0 ? '+${_fmtCount(newThisMonth)} this month' : null,
            value: counter(inUse.toDouble(), (v) => _fmtCount(v.round()), _StatRow.numberStyle(c)),
            icon: Icons.inventory_2_rounded,
            dot: Ios.green,
            semantics: '${_fmtCount(inUse)} assets in use. Open Assets.',
            onTap: () => context.go('/assets'), // bottom-bar tab
          ),
          const Divider(height: 1, indent: 60),
          _StatRow(
            label: 'Under repair',
            value: counter(underRepair.toDouble(), (v) => _fmtCount(v.round()), _StatRow.numberStyle(c)),
            icon: Icons.build_rounded,
            dot: Ios.orange,
            semantics: '${_fmtCount(underRepair)} under repair. Open Maintenance.',
            onTap: () => context.push('/maintenance'),
          ),
          const Divider(height: 1, indent: 60),
          _StatRow(
            label: 'For disposal',
            value: counter(forDisposal.toDouble(), (v) => _fmtCount(v.round()), _StatRow.numberStyle(c)),
            icon: Icons.delete_rounded,
            dot: Ios.red,
            semantics: '${_fmtCount(forDisposal)} for disposal. Open Disposal.',
            onTap: () => context.push('/disposal'),
          ),
        ],
      ),
    );
  }
}

/// A non-zero count never shows as 0% (same rule as the web dashboard).
String _fmtPct(int count, int total) {
  if (total == 0 || count == 0) return '0%';
  final pct = (count * 100 / total).round();
  return pct == 0 ? '<1%' : '$pct%';
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
  final String? badge;
  final Widget value;
  final IconData icon;
  final Color dot;
  final String semantics;
  final VoidCallback onTap;

  const _StatRow({
    required this.label,
    this.badge,
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label,
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w400, letterSpacing: -0.3, color: c.textPrimary)),
                      // "+12 this month" - the web stat card's green delta
                      if (badge != null)
                        Text(badge!, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppTheme.brandButton)),
                    ],
                  ),
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
  final String? footer;

  const _DistributionCard({
    required this.icon,
    required this.accent,
    required this.title,
    required this.total,
    required this.dist,
    required this.order,
    required this.colorOf,
    required this.labelOf,
    this.footer,
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
      headlineUnit: total == 0 ? null : 'assets',
      child: total == 0
          ? Text('No assets registered yet.', style: TextStyle(color: c.textSecondary, fontSize: 15))
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
                if (footer != null) ...[
                  const Divider(height: 1),
                  const SizedBox(height: 10),
                  Text(footer!, style: TextStyle(fontSize: 14.5, color: c.textSecondary)),
                ],
              ],
            ),
    );
  }
}

/// Assets by Office / by Category: one row per group with its count, and a thin bar scaled to
/// the largest group (so a share-of-total is only shown when [shareOf] is given).
class _BarListCard extends StatelessWidget {
  final IconData icon;
  final Color accent;
  final String title;
  final String caption;
  final List<DashboardGroup> groups;
  final Color barColor;
  final int? shareOf;
  final String emptyMessage;

  const _BarListCard({
    required this.icon,
    required this.accent,
    required this.title,
    required this.caption,
    required this.groups,
    required this.barColor,
    required this.emptyMessage,
    this.shareOf,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final max = groups.isEmpty ? 1 : groups.first.count.clamp(1, 1 << 31);
    final still = context.prefersReducedMotion;

    return _SummaryCard(
      icon: icon,
      accent: accent,
      title: title,
      trailing: groups.isEmpty
          ? null
          : Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Text(caption, style: TextStyle(fontSize: 14, color: c.textTertiary)),
            ),
      child: groups.isEmpty
          ? Text(emptyMessage, style: TextStyle(color: c.textSecondary, fontSize: 15))
          : Column(
              children: [
                for (var i = 0; i < groups.length; i++) ...[
                  if (i > 0) const SizedBox(height: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(groups[i].name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 16, letterSpacing: -0.3, color: c.textPrimary)),
                          ),
                          const SizedBox(width: 8),
                          Text(_fmtCount(groups[i].count),
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: -0.2, color: c.textPrimary)),
                          if (shareOf != null)
                            SizedBox(
                              width: 50,
                              child: Text(_fmtPct(groups[i].count, shareOf!),
                                  textAlign: TextAlign.right, style: TextStyle(fontSize: 15, color: c.textTertiary)),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: Container(
                          height: 6,
                          color: c.border.withValues(alpha: 0.5),
                          alignment: Alignment.centerLeft,
                          child: TweenAnimationBuilder<double>(
                            // Reduce Motion: drawn at full length, no grow
                            tween: Tween(begin: still ? 1 : 0, end: 1),
                            duration: still ? Duration.zero : AppTheme.motionSlow,
                            curve: AppTheme.motionCurve,
                            builder: (context, progress, _) => FractionallySizedBox(
                              widthFactor: (groups[i].count / max * progress).clamp(0.0, 1.0),
                              child: Container(
                                decoration: BoxDecoration(color: barColor, borderRadius: BorderRadius.circular(3)),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
    );
  }
}
