import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../model/asset_model.dart';
import '../provider/asset_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/ui.dart' show toolbarButtonStyle;
import '../../../shared/widgets/status_badge.dart';
import '../../../shared/widgets/paginated_list_view.dart';
import '../../../shared/widgets/auto_refresh_ticker.dart';
import '../../../shared/widgets/app_search_field.dart';
import '../../../shared/widgets/main_shell.dart';
import '../../../shared/widgets/large_title_scaffold.dart';
import '../../../core/platform.dart';
import '../../../core/api/api_exception.dart';
import '../data/asset_service.dart';
import '../utils/asset_excel.dart';
import '../widgets/asset_filter_sheet.dart';
import '../../auth/provider/auth_provider.dart';
import '../../../shared/widgets/ios_touch.dart';

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
    final isAdmin = ref.watch(authProvider).valueOrNull?.isAdmin ?? false;
    final search = ref.watch(assetSearchProvider);
    final state = ref.watch(assetsPagedProvider(search));
    final countAsync = ref.watch(assetCountProvider(search));
    final filtersActive = assetFiltersActive(ref);

    Future<void> addAsset() async {
      final result = await context.push<bool>('/assets/new');
      if (result == true) {
        ref.invalidate(assetsPagedProvider(search));
        ref.invalidate(assetCountProvider(search));
      }
    }

    return LargeTitleScaffold(
      title: 'Assets',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isDesktopPlatform)
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'Refresh',
              onPressed: () {
                ref.invalidate(assetsPagedProvider(search));
                ref.invalidate(assetCountProvider(search));
              },
            ),
        ],
      ),
      bottom: PreferredSize(
          preferredSize: Size.fromHeight(isAdmin ? 204 : 146),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              children: [
                // record count under the large title
                SizedBox(
                  height: 22,
                  child: Align(
                    alignment: Alignment.topCenter, // under the centred title
                    // the number in bold primary text so it reads at a glance; the word stays quiet
                    child: Text.rich(
                      countAsync.when(
                        data: (c) => TextSpan(children: [
                          TextSpan(
                            text: _withCommas(c),
                            style: TextStyle(fontWeight: FontWeight.w700, color: context.colors.textPrimary),
                          ),
                          TextSpan(text: c == 1 ? ' record' : ' records'),
                        ]),
                        loading: () => const TextSpan(text: ' '),
                        error: (_, __) => const TextSpan(text: ' '),
                      ),
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: context.colors.textTertiary),
                    ),
                  ),
                ),
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
                // Adding is ADMIN-only. A full-width button here, like Add Office and New Account,
                // rather than a small "+ Add" in the corner of the bar that was easy to miss.
                if (isAdmin) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton.icon(
                      icon: const Icon(Icons.add_rounded, size: 20),
                      label: const Text('Add Asset'),
                      onPressed: addAsset,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      body: AutoRefreshTicker(
        interval: const Duration(seconds: 30),
        onTick: () => ref.read(assetsPagedProvider(search).notifier).silentRefresh(),
        // One card per asset, same as the web list (grouping was retired with the single-quantity model).
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

  ButtonStyle _toolbarButton(BuildContext context, {bool active = false}) =>
      toolbarButtonStyle(context, active: active);
}

class _AssetCard extends StatelessWidget {
  final AssetModel asset;
  final VoidCallback onTap;

  const _AssetCard({required this.asset, required this.onTap});

  @override
  Widget build(BuildContext context) {
    // An older record that counted several devices in one row (Qty > 1) but only stored
    // one set of numbers - flagged so it can be edited into separate devices.
    final legacyMulti = asset.groupId == null && asset.quantity >= 2;
    final c = context.colors;
    // shrinks a touch on press, like an iOS list row
    return PressScale(
      scale: 0.98,
      child: Card(
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
                        'Counts ${asset.quantity} devices but only one is recorded. Edit to add the others.',
                        style: TextStyle(
                          color: context.isLight ? const Color(0xFFB45309) : const Color(0xFFFBBF24),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const DisclosureChevron(),
            ],
          ),
        ),
      ),
    ),
    );
  }
}

/// 2417 → "2,417".
String _withCommas(int n) =>
    n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
