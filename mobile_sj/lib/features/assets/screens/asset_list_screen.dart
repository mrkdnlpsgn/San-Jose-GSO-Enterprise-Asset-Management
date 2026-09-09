import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../model/asset_model.dart';
import '../provider/asset_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/status_badge.dart';
import '../../../shared/widgets/paginated_list_view.dart';
import '../../../shared/widgets/auto_refresh_ticker.dart';
import '../../../shared/widgets/app_search_field.dart';
import '../../../shared/widgets/main_shell.dart';
import '../../../core/platform.dart';
import '../../../core/api/api_exception.dart';
import '../data/asset_service.dart';
import '../utils/asset_excel.dart';
import '../widgets/asset_filter_sheet.dart';

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
        child: PaginatedListView<AssetModel>(
          state: state,
          emptyMessage: 'No assets found.',
          extraBottomPadding: context.mainShellBottomInset,
          onLoadMore: () => ref.read(assetsPagedProvider(search).notifier).loadMore(),
          onRefresh: () async {
            ref.invalidate(assetCountProvider(search));
            await ref.read(assetsPagedProvider(search).notifier).refresh();
          },
          itemBuilder: (context, asset, i) => _AssetCard(
            asset: asset,
            onTap: () => context.push('/assets/${asset.id}'),
          ),
        ),
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
                    child: Text(asset.propertyNumber,
                        style: const TextStyle(color: AppTheme.brand, fontSize: 12, fontWeight: FontWeight.w600)),
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
            ],
          ),
        ),
      ),
    );
  }
}
