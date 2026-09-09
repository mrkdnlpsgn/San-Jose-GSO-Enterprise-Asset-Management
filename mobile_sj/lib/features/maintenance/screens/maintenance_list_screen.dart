import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../model/maintenance_model.dart';
import '../provider/maintenance_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/paginated_list_view.dart';
import '../../../shared/widgets/auto_refresh_ticker.dart';
import '../../../shared/widgets/app_search_field.dart';
import '../../../shared/widgets/status_badge.dart';
import '../../../features/auth/provider/auth_provider.dart';
import '../../../core/platform.dart';
import '../widgets/maintenance_filter_sheet.dart';

class MaintenanceListScreen extends ConsumerStatefulWidget {
  const MaintenanceListScreen({super.key});

  @override
  ConsumerState<MaintenanceListScreen> createState() => _MaintenanceListScreenState();
}

class _MaintenanceListScreenState extends ConsumerState<MaintenanceListScreen> {
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final search = ref.watch(maintenanceSearchProvider);
    final state = ref.watch(maintenancePagedProvider(search));
    final countAsync = ref.watch(maintenanceCountProvider(search));
    final isAdmin = ref.watch(authProvider).value?.isAdmin ?? false;
    final filtersActive = maintenanceFiltersActive(ref);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Maintenance'),
            Text(
              countAsync.when(
                data: (c) => '$c ${c == 1 ? 'record' : 'records'}',
                loading: () => ' ',
                error: (_, __) => ' ',
              ),
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.normal, color: context.colors.textSecondary),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: AnimatedSwitcher(
              duration: AppTheme.motionFast,
              switchInCurve: AppTheme.motionCurve,
              switchOutCurve: AppTheme.motionCurve,
              transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: child),
              child: Badge(
                key: ValueKey(filtersActive),
                isLabelVisible: filtersActive,
                smallSize: 8,
                child: const Icon(Icons.filter_list_rounded),
              ),
            ),
            tooltip: 'Filter',
            onPressed: () => showMaintenanceFilterSheet(context, ref),
          ),
          if (isDesktopPlatform)
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              onPressed: () {
                ref.invalidate(maintenancePagedProvider(search));
                ref.invalidate(maintenanceCountProvider(search));
              },
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(64),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: AppSearchField(
              controller: _searchCtrl,
              hintText: 'Search maintenance records...',
              onChanged: (v) => ref.read(maintenanceSearchProvider.notifier).state = v,
            ),
          ),
        ),
      ),
      floatingActionButton: isAdmin
          ? FloatingActionButton(
              backgroundColor: AppTheme.brand,
              child: const Icon(Icons.add_rounded, color: Colors.white),
              onPressed: () async {
                final result = await context.push<bool>('/maintenance/new');
                if (result == true) {
                  ref.invalidate(maintenancePagedProvider(search));
                  ref.invalidate(maintenanceCountProvider(search));
                }
              },
            )
          : null,
      body: AutoRefreshTicker(
        interval: const Duration(seconds: 30),
        onTick: () => ref.read(maintenancePagedProvider(search).notifier).silentRefresh(),
        child: PaginatedListView<MaintenanceModel>(
          state: state,
          emptyMessage: 'No maintenance records.',
          onLoadMore: () => ref.read(maintenancePagedProvider(search).notifier).loadMore(),
          onRefresh: () async {
            ref.invalidate(maintenanceCountProvider(search));
            await ref.read(maintenancePagedProvider(search).notifier).refresh();
          },
          itemBuilder: (context, item, i) => _MaintenanceCard(
            item: item,
            onTap: () => context.push('/maintenance/${item.id}'),
          ),
        ),
      ),
    );
  }
}

class _MaintenanceCard extends StatelessWidget {
  final MaintenanceModel item;
  final VoidCallback onTap;

  const _MaintenanceCard({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  StatusBadge.maintenanceType(item.maintenanceType, dense: true),
                  const Spacer(),
                  StatusBadge.maintenanceStatus(item.status, dense: true),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                item.asset.description,
                style: TextStyle(color: context.colors.textPrimary, fontSize: 15, fontWeight: FontWeight.w500),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                item.asset.propertyNumber,
                style: const TextStyle(color: AppTheme.brand, fontSize: 12),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.calendar_today_outlined, size: 13, color: context.colors.textSecondary),
                  const SizedBox(width: 4),
                  Text(item.maintenanceDate, style: TextStyle(color: context.colors.textTertiary, fontSize: 12)),
                  if (item.assignedTo != null) ...[
                    const SizedBox(width: 12),
                    Icon(Icons.person_outline_rounded, size: 13, color: context.colors.textSecondary),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(item.assignedTo!, style: TextStyle(color: context.colors.textTertiary, fontSize: 12), overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
