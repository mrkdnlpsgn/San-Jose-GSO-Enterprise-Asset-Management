import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../model/maintenance_model.dart';
import '../provider/maintenance_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/paginated_list_view.dart';
import '../../../shared/widgets/auto_refresh_ticker.dart';
import '../../../shared/widgets/status_badge.dart';
import '../../../shared/widgets/ui.dart';
import '../../reports/utils/formatters.dart';
import '../../../core/platform.dart';
import '../widgets/maintenance_filter_sheet.dart';
import '../../assets/widgets/asset_group_widgets.dart';

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
    final filtersActive = maintenanceFiltersActive(ref);

    return Scaffold(
      appBar: AppBar(
        title: TitleWithCount('Maintenance', subtitle: countLabel(countAsync.valueOrNull)),
        actions: [
          if (isDesktopPlatform)
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'Refresh',
              onPressed: () {
                ref.invalidate(maintenancePagedProvider(search));
                ref.invalidate(maintenanceCountProvider(search));
              },
            ),
        ],
        bottom: ListToolbar(
          controller: _searchCtrl,
          hintText: 'Search maintenance records',
          onSearch: (v) => ref.read(maintenanceSearchProvider.notifier).state = v,
          onFilter: () => showMaintenanceFilterSheet(context, ref),
          filtersActive: filtersActive,
        ),
      ),
      body: AutoRefreshTicker(
        interval: const Duration(seconds: 30),
        onTick: () => ref.read(maintenancePagedProvider(search).notifier).silentRefresh(),
        child: PaginatedListView<RecordEntry<MaintenanceModel>>(
          state: groupRecordsState(state, (m) => m.asset.groupId),
          emptyMessage: 'No maintenance records.',
          onLoadMore: () => ref.read(maintenancePagedProvider(search).notifier).loadMore(),
          onRefresh: () async {
            ref.invalidate(maintenanceCountProvider(search));
            await ref.read(maintenancePagedProvider(search).notifier).refresh();
          },
          itemBuilder: (context, entry, i) => entry.isGroup
              ? RecordGroupCard<MaintenanceModel>(
                  members: entry.members,
                  assetOf: (m) => m.asset,
                  noun: 'records',
                  columns: const ['Asset', 'Type', 'Findings', 'Status', 'Date', 'Assigned To', 'Cost'],
                  values: (m) => [
                    assetCellText(m.asset),
                    m.maintenanceType,
                    m.findings,
                    m.status,
                    m.maintenanceDate,
                    m.assignedTo ?? 'N/A',
                    fmtMoney(m.cost),
                  ],
                  summary: Text(
                    'Total cost ${fmtMoney(entry.members.fold<double>(0, (n, m) => n + (m.cost ?? 0)))}',
                    style: TextStyle(color: context.colors.textTertiary, fontSize: 14),
                  ),
                  onOpenRecord: (m) => context.push('/maintenance/${m.id}'),
                  onOpenDevice: (a) => context.push('/assets/${a.id}'),
                )
              : _MaintenanceCard(
                  item: entry.members.first,
                  onTap: () => context.push('/maintenance/${entry.members.first.id}'),
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
    return RecordCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CodeText(item.asset.propertyAndPar),
          const SizedBox(height: 4),
          CardTitle(item.asset.description, maxLines: 1),
          const SizedBox(height: 6),
          MetaLine(Icons.event_rounded, fmtDate(item.maintenanceDate)),
          if (item.assignedTo != null) ...[
            const SizedBox(height: 4),
            MetaLine(Icons.person_rounded, item.assignedTo!),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              StatusBadge.maintenanceStatus(item.status),
              StatusBadge.maintenanceType(item.maintenanceType),
              if (StatusBadge.approval(item.approvalStatus) case final badge?) badge,
            ],
          ),
        ],
      ),
    );
  }
}
