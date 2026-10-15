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
import '../../reports/utils/formatters.dart';
import '../../auth/provider/auth_provider.dart';

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
    // Adding and importing assets is ADMIN-only (web parity); staff edit their office's.
    final isAdmin = ref.watch(authProvider).value?.isAdmin ?? false;
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
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: context.colors.textTertiary),
            ),
          ],
        ),
        actions: [
          if (isDesktopPlatform)
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'Refresh',
              onPressed: () {
                ref.invalidate(assetsPagedProvider(search));
                ref.invalidate(assetCountProvider(search));
              },
            ),
          // "Add Asset" sits in the top bar like the web page's green button — no floating button
          if (isAdmin)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FilledButton.icon(
                icon: const Icon(Icons.add_rounded, size: 20),
                label: const Text('Add Asset'),
                style: FilledButton.styleFrom(minimumSize: const Size(0, 42), padding: const EdgeInsets.symmetric(horizontal: 14)),
                onPressed: () async {
                  final result = await context.push<bool>('/assets/new');
                  if (result == true) {
                    ref.invalidate(assetsPagedProvider(search));
                    ref.invalidate(assetCountProvider(search));
                  }
                },
              ),
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(124),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              children: [
                AppSearchField(
                  controller: _searchCtrl,
                  hintText: 'Search property no. or description',
                  onChanged: (v) => ref.read(assetSearchProvider.notifier).state = v,
                ),
                const SizedBox(height: 10),
                // Worded buttons, as on the web page, instead of icons hidden in a ⋮ menu
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: Badge(
                          isLabelVisible: filtersActive,
                          smallSize: 8,
                          backgroundColor: AppTheme.brand,
                          child: const Icon(Icons.filter_list_rounded, size: 20),
                        ),
                        label: Text(filtersActive ? 'Filters on' : 'Filter'),
                        style: _toolbarButton(context, active: filtersActive),
                        onPressed: () => showAssetFilterSheet(context, ref),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: _exporting
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.file_download_outlined, size: 20),
                        label: const Text('Export'),
                        style: _toolbarButton(context),
                        onPressed: _exporting ? null : _export,
                      ),
                    ),
                    if (isAdmin) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.file_upload_outlined, size: 20),
                          label: const Text('Import'),
                          style: _toolbarButton(context),
                          onPressed: () async {
                            final result = await context.push<bool>('/assets/import');
                            if (result == true) {
                              ref.invalidate(assetsPagedProvider(search));
                              ref.invalidate(assetCountProvider(search));
                            }
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
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

  ButtonStyle _toolbarButton(BuildContext context, {bool active = false}) => OutlinedButton.styleFrom(
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        backgroundColor: active ? (context.isLight ? AppTheme.brandTint : AppTheme.brand.withValues(alpha: 0.15)) : context.colors.surface,
        foregroundColor: active ? context.brandAccent : context.colors.textPrimary,
        side: BorderSide(color: active ? AppTheme.brand : (context.isLight ? const Color(0xFFCBD5E1) : context.colors.border)),
      );
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
    final accent = context.brandAccent;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
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
                                color: context.colors.textPrimary, fontSize: 16, fontWeight: FontWeight.w600),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(Icons.apartment_rounded, size: 16, color: context.colors.textTertiary),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(offices.length == 1 ? offices.first : 'Multiple locations',
                                  style: TextStyle(color: context.colors.textSecondary, fontSize: 14),
                                  overflow: TextOverflow.ellipsis),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text('Total value ${fmtMoney(total)}',
                            style: TextStyle(color: context.colors.textTertiary, fontSize: 14)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  StatusBadge(label: '$count devices', color: AppTheme.gov),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Group details & lifecycle',
                    icon: Icon(Icons.info_outline_rounded, color: accent),
                    onPressed: () => showAssetGroupSheet(
                      context,
                      groupId: _groupId,
                      description: first.description,
                      onOpenDevice: widget.onOpen,
                    ),
                  ),
                  Icon(_expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: accent),
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
                              child: CircularProgressIndicator(strokeWidth: 2))),
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
    final c = context.colors;
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Property no. in the monospace style the web table uses
                    Text(asset.propertyAndPar,
                        style: TextStyle(
                          color: c.textTertiary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'monospace',
                          letterSpacing: -0.2,
                        ),
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Text(asset.description,
                        style: TextStyle(color: c.textPrimary, fontSize: 16, fontWeight: FontWeight.w600, height: 1.3),
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.apartment_rounded, size: 16, color: c.textTertiary),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(asset.office.officeName,
                              style: TextStyle(color: c.textSecondary, fontSize: 14), overflow: TextOverflow.ellipsis),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        StatusBadge.condition(asset.condition),
                        StatusBadge.lifecycle(asset.lifecycleStatus),
                      ],
                    ),
                    if (legacyMulti) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Counts ${asset.quantity} devices but only one is recorded — edit to add the others.',
                        style: TextStyle(
                          color: context.isLight ? const Color(0xFFB45309) : const Color(0xFFFBBF24),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right_rounded, color: c.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}
