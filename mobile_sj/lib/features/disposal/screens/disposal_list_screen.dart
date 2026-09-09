import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../model/disposal_model.dart';
import '../provider/disposal_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/paginated_list_view.dart';
import '../../../shared/widgets/auto_refresh_ticker.dart';
import '../../../shared/widgets/app_search_field.dart';
import '../../../shared/widgets/status_badge.dart';
import '../../../features/auth/provider/auth_provider.dart';
import '../../../core/platform.dart';
import '../widgets/disposal_filter_sheet.dart';

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
    final isAdmin = ref.watch(authProvider).value?.isAdmin ?? false;
    final filtersActive = disposalFiltersActive(ref);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Disposal'),
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
            onPressed: () => showDisposalFilterSheet(context, ref),
          ),
          if (isDesktopPlatform)
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              onPressed: () {
                ref.invalidate(disposalPagedProvider(search));
                ref.invalidate(disposalCountProvider(search));
              },
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(64),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: AppSearchField(
              controller: _searchCtrl,
              hintText: 'Search disposal records...',
              onChanged: (v) => ref.read(disposalSearchProvider.notifier).state = v,
            ),
          ),
        ),
      ),
      floatingActionButton: isAdmin
          ? FloatingActionButton(
              backgroundColor: AppTheme.brand,
              child: const Icon(Icons.add_rounded, color: Colors.white),
              onPressed: () async {
                final result = await context.push<bool>('/disposal/new');
                if (result == true) {
                  ref.invalidate(disposalPagedProvider(search));
                  ref.invalidate(disposalCountProvider(search));
                }
              },
            )
          : null,
      body: AutoRefreshTicker(
        interval: const Duration(seconds: 30),
        onTick: () => ref.read(disposalPagedProvider(search).notifier).silentRefresh(),
        child: PaginatedListView<DisposalModel>(
          state: state,
          emptyMessage: 'No disposal records.',
          onLoadMore: () => ref.read(disposalPagedProvider(search).notifier).loadMore(),
          onRefresh: () async {
            ref.invalidate(disposalCountProvider(search));
            await ref.read(disposalPagedProvider(search).notifier).refresh();
          },
          itemBuilder: (context, item, i) => _DisposalCard(
            item: item,
            onTap: () => context.push('/disposal/${item.id}'),
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
                  StatusBadge.disposalMethod(item.recommendedMethod, dense: true),
                  const Spacer(),
                  StatusBadge.disposalStatus(item.disposalStatus, dense: true),
                ],
              ),
              const SizedBox(height: 8),
              Text(item.asset.description,
                  style: TextStyle(color: context.colors.textPrimary, fontSize: 15, fontWeight: FontWeight.w500),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 4),
              Text(item.asset.propertyNumber, style: const TextStyle(color: AppTheme.brand, fontSize: 12)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.calendar_today_outlined, size: 13, color: context.colors.textSecondary),
                  const SizedBox(width: 4),
                  Text(item.inspectionDate, style: TextStyle(color: context.colors.textTertiary, fontSize: 12)),
                  if (item.approvedBy != null) ...[
                    const SizedBox(width: 12),
                    Icon(Icons.verified_outlined, size: 13, color: context.colors.textSecondary),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(item.approvedBy!,
                          style: TextStyle(color: context.colors.textTertiary, fontSize: 12),
                          overflow: TextOverflow.ellipsis),
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
