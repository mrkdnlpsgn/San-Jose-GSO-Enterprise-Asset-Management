import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../model/disposal_model.dart';
import '../provider/disposal_provider.dart';
import '../../../shared/widgets/paginated_list_view.dart';
import '../../../shared/widgets/auto_refresh_ticker.dart';
import '../../../shared/widgets/status_badge.dart';
import '../../../shared/widgets/ui.dart';
import '../../reports/utils/formatters.dart';
import '../../../core/platform.dart';
import '../widgets/disposal_filter_sheet.dart';
import '../../assets/widgets/asset_group_widgets.dart';

class DisposalListScreen extends ConsumerStatefulWidget {
  const DisposalListScreen({super.key});

  @override
  ConsumerState<DisposalListScreen> createState() => _DisposalListScreenState();
}

class _DisposalListScreenState extends ConsumerState<DisposalListScreen> {
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final search = ref.watch(disposalSearchProvider);
    final state = ref.watch(disposalPagedProvider(search));
    final countAsync = ref.watch(disposalCountProvider(search));
    final filtersActive = disposalFiltersActive(ref);

    return Scaffold(
      appBar: AppBar(
        title: TitleWithCount('Disposal', subtitle: countLabel(countAsync.valueOrNull)),
        actions: [
          if (isDesktopPlatform)
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'Refresh',
              onPressed: () {
                ref.invalidate(disposalPagedProvider(search));
                ref.invalidate(disposalCountProvider(search));
              },
            ),
        ],
        bottom: ListToolbar(
          controller: _searchCtrl,
          hintText: 'Search disposal records',
          onSearch: (v) => ref.read(disposalSearchProvider.notifier).state = v,
          onFilter: () => showDisposalFilterSheet(context, ref),
          filtersActive: filtersActive,
        ),
      ),
      body: AutoRefreshTicker(
        interval: const Duration(seconds: 30),
        onTick: () => ref.read(disposalPagedProvider(search).notifier).silentRefresh(),
        child: PaginatedListView<RecordEntry<DisposalModel>>(
          state: groupRecordsState(state, (d) => d.asset.groupId),
          emptyMessage: 'No disposal records.',
          onLoadMore: () => ref.read(disposalPagedProvider(search).notifier).loadMore(),
          onRefresh: () async {
            ref.invalidate(disposalCountProvider(search));
            await ref.read(disposalPagedProvider(search).notifier).refresh();
          },
          itemBuilder: (context, entry, i) => entry.isGroup
              ? RecordGroupCard<DisposalModel>(
                  members: entry.members,
                  assetOf: (d) => d.asset,
                  noun: 'records',
                  columns: const ['Asset', 'Reason', 'Method', 'Status', 'Inspection Date', 'Approved By', 'Recorded By'],
                  values: (d) => [
                    assetCellText(d.asset),
                    d.reason,
                    d.recommendedMethod,
                    d.disposalStatus,
                    d.inspectionDate,
                    d.approvedBy ?? '—',
                    d.recordedBy.fullName,
                  ],
                  onOpenRecord: (d) => context.push('/disposal/${d.id}'),
                  onOpenDevice: (a) => context.push('/assets/${a.id}'),
                )
              : _DisposalCard(
                  item: entry.members.first,
                  onTap: () => context.push('/disposal/${entry.members.first.id}'),
                ),
        ),
      ),
    );
  }
}

class _DisposalCard extends StatelessWidget {
  final DisposalModel item;
  final VoidCallback onTap;
  const _DisposalCard({required this.item, required this.onTap});

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
          MetaLine(Icons.event_rounded, 'Inspected ${fmtDate(item.inspectionDate)}'),
          if (item.approvedBy != null) ...[
            const SizedBox(height: 4),
            MetaLine(Icons.verified_rounded, 'Approved by ${item.approvedBy!}'),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              StatusBadge.disposalStatus(item.disposalStatus),
              StatusBadge.disposalMethod(item.recommendedMethod),
              if (StatusBadge.approval(item.approvalStatus) case final badge?) badge,
            ],
          ),
        ],
      ),
    );
  }
}
