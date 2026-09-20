import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../model/asset_model.dart';
import '../provider/asset_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/status_badge.dart';
import '../../../shared/widgets/paginated_list_view.dart';
import '../../../shared/provider/paginated_list_notifier.dart';
import '../../../shared/widgets/auto_refresh_ticker.dart';
import '../../../shared/widgets/app_search_field.dart';
import '../../../shared/widgets/main_shell.dart';
import '../../../core/platform.dart';
import '../../../core/api/api_exception.dart';
import '../data/asset_service.dart';
import '../utils/asset_excel.dart';
import '../widgets/asset_filter_sheet.dart';
import '../widgets/asset_group_widgets.dart';

class AssetListScreen extends ConsumerStatefulWidget {
  const AssetListScreen({super.key});

  @override
  ConsumerState<AssetListScreen> createState() => _AssetListScreenState();
}

class _AssetListScreenState extends ConsumerState<AssetListScreen> {
  final _searchCtrl = TextEditingController();
  bool _exporting = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _export() async {
    setState(() => _exporting = true);
    try {
      final assets = await AssetService().getAll(size: 100000);
      if (!mounted) return;
      if (assets.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No assets to export.'), behavior: SnackBarBehavior.floating),
        );
        return;
      }
      await exportAssetsToExcel(assets);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.red.shade800, behavior: SnackBarBehavior.floating),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final search = ref.watch(assetSearchProvider);
    final state = ref.watch(assetsPagedProvider(search));
    final countAsync = ref.watch(assetCountProvider(search));
    final filtersActive = assetFiltersActive(ref);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Assets'),
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
            onPressed: () => showAssetFilterSheet(context, ref),
          ),
          if (isDesktopPlatform)
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              onPressed: () {
                ref.invalidate(assetsPagedProvider(search));
                ref.invalidate(assetCountProvider(search));
              },
            ),
          PopupMenuButton<String>(
            icon: _exporting
                ? const SizedBox(width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.brand))
                : const Icon(Icons.more_vert_rounded),
            onSelected: (value) async {
              if (value == 'export') {
                await _export();
              } else if (value == 'import') {
                final result = await context.push<bool>('/assets/import');
                if (result == true) {
                  ref.invalidate(assetsPagedProvider(search));
                  ref.invalidate(assetCountProvider(search));
                }
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'export', child: Row(children: [
                Icon(Icons.file_download_outlined, size: 18), SizedBox(width: 10), Text('Export'),
              ])),
              PopupMenuItem(value: 'import', child: Row(children: [
                Icon(Icons.file_upload_outlined, size: 18), SizedBox(width: 10), Text('Import'),
              ])),
            ],
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(64),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: AppSearchField(
              controller: _searchCtrl,
              hintText: 'Search by property number, description...',
              onChanged: (v) => ref.read(assetSearchProvider.notifier).state = v,
            ),
          ),
        ),
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: kMainShellBarHeight),
        child: FloatingActionButton(
          backgroundColor: AppTheme.brand,
          child: const Icon(Icons.add_rounded, color: Colors.white),
          onPressed: () async {
            final result = await context.push<bool>('/assets/new');
            if (result == true) {
              ref.invalidate(assetsPagedProvider(search));
              ref.invalidate(assetCountProvider(search));
            }
          },
        ),
      ),
      body: AutoRefreshTicker(
        interval: const Duration(seconds: 30),
        onTick: () => ref.read(assetsPagedProvider(search).notifier).silentRefresh(),
        child: PaginatedListView<_AssetEntry>(
          state: _groupedState(state),
          emptyMessage: 'No assets found.',
          extraBottomPadding: context.mainShellBottomInset,
          onLoadMore: () => ref.read(assetsPagedProvider(search).notifier).loadMore(),
          onRefresh: () async {
            ref.invalidate(assetCountProvider(search));
            await ref.read(assetsPagedProvider(search).notifier).refresh();
          },
          itemBuilder: (context, entry, i) => entry.isGroup
              ? _AssetGroupCard(members: entry.members, onOpen: (a) => context.push('/assets/${a.id}'))
              : _AssetCard(
                  asset: entry.members.first,
                  onTap: () => context.push('/assets/${entry.members.first.id}'),
                ),
        ),
      ),
    );
  }
}

// One row in the list: a single asset, or a group of same-model devices that were
// added together (shared groupId). Every member of a group is still a complete asset.
class _AssetEntry {
  final List<AssetModel> members;
  const _AssetEntry(this.members);
  bool get isGroup => members.length > 1 || (members.first.groupSize ?? 0) > 1;
}

// Groups assets that share a groupId (first occurrence keeps its position). A group with
// only one loaded member renders as a normal card. Pages are loaded 20 assets at a time,
// so a group whose devices land on different pages simply fills in as more are loaded.
PaginatedListState<_AssetEntry> _groupedState(PaginatedListState<AssetModel> s) {
  final entries = <_AssetEntry>[];
  final byGroup = <String, List<AssetModel>>{};
  for (final a in s.items) {
    final g = a.groupId;
    if (g == null) {
      entries.add(_AssetEntry([a]));
    } else if (byGroup.containsKey(g)) {
      byGroup[g]!.add(a);
    } else {
      final members = <AssetModel>[a];
      byGroup[g] = members;
      entries.add(_AssetEntry(members));
    }
  }
  return PaginatedListState<_AssetEntry>(
    items: entries,
    isLoading: s.isLoading,
    isLoadingMore: s.isLoadingMore,
    hasMore: s.hasMore,
    error: s.error,
    loadMoreError: s.loadMoreError,
  );
}

class _AssetGroupCard extends StatefulWidget {
  final List<AssetModel> members;
  final void Function(AssetModel) onOpen;

  const _AssetGroupCard({required this.members, required this.onOpen});

  @override
  State<_AssetGroupCard> createState() => _AssetGroupCardState();
}

class _AssetGroupCardState extends State<_AssetGroupCard> {
  bool _expanded = false;
  Future<List<AssetModel>>? _all; // every device of the group, fetched when first expanded

  String get _groupId => widget.members.first.groupId!;

  @override
  Widget build(BuildContext context) {
    final members = widget.members;
    final first = members.first;
    // Header numbers come from the server's roll-up, so they're right even if only some of
    // the group's devices are loaded in this list.
    final count = first.groupSize ?? members.length;
    final total = first.groupTotalValue ?? members.fold<double>(0, (n, m) => n + m.unitValue * m.quantity);
    final offices = members.map((m) => m.office.officeName).toSet();
    return Card(
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() {
              _expanded = !_expanded;
              _all ??= AssetService().getGroup(_groupId);
            }),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(first.description,
                            style: TextStyle(
                                color: context.colors.textPrimary, fontSize: 15, fontWeight: FontWeight.w500),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(Icons.business_outlined, size: 13, color: context.colors.textSecondary),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(offices.length == 1 ? offices.first : 'Multiple locations',
                                  style: TextStyle(color: context.colors.textTertiary, fontSize: 12),
                                  overflow: TextOverflow.ellipsis),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text('Total value ₱${total.toStringAsFixed(2)}',
                            style: TextStyle(color: context.colors.textSecondary, fontSize: 12)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppTheme.brand.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text('$count devices',
                        style: const TextStyle(color: AppTheme.brand, fontSize: 11.5, fontWeight: FontWeight.w600)),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Group details & lifecycle',
                    icon: const Icon(Icons.info_outline_rounded, color: AppTheme.brand),
                    onPressed: () => showAssetGroupSheet(
                      context,
                      groupId: _groupId,
                      description: first.description,
                      onOpenDevice: widget.onOpen,
                    ),
                  ),
                  Icon(_expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: AppTheme.brand),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
              child: FutureBuilder<List<AssetModel>>(
                future: _all,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(
                          child: SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.brand))),
                    );
                  }
                  // If the fetch fails, fall back to whichever devices are already loaded.
                  final all = snap.hasError ? members : snap.data!;
                  return GroupDevicesTable(members: all, onOpen: widget.onOpen);
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _AssetCard extends StatelessWidget {
  final AssetModel asset;
  final VoidCallback onTap;

  const _AssetCard({required this.asset, required this.onTap});

  @override
  Widget build(BuildContext context) {
    // An older record that counted several devices in one row (Qty > 1) but only stored
    // one set of numbers — flagged so it can be edited into separate devices.
    final legacyMulti = asset.groupId == null && asset.quantity >= 2;
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
                  Expanded(
                    child: Text(asset.propertyAndPar,
                        style: const TextStyle(color: AppTheme.brand, fontSize: 12, fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis),
                  ),
                  StatusBadge.lifecycle(asset.lifecycleStatus),
                ],
              ),
              const SizedBox(height: 6),
              Text(asset.description,
                  style: TextStyle(color: context.colors.textPrimary, fontSize: 15, fontWeight: FontWeight.w500),
                  maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.business_outlined, size: 13, color: context.colors.textSecondary),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(asset.office.officeName,
                        style: TextStyle(color: context.colors.textTertiary, fontSize: 12),
                        overflow: TextOverflow.ellipsis),
                  ),
                  const SizedBox(width: 8),
                  StatusBadge.condition(asset.condition),
                ],
              ),
              if (legacyMulti) ...[
                const SizedBox(height: 8),
                Text(
                  'Counts ${asset.quantity} devices but only one is recorded — edit to add the others.',
                  style: const TextStyle(color: Colors.amber, fontSize: 11.5, fontStyle: FontStyle.italic),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
