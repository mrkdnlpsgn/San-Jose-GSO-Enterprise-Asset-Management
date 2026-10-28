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
import '../widgets/asset_qr_sheet.dart' show showQrExportSheet;
import '../../auth/provider/auth_provider.dart';
import '../../../shared/widgets/ios_touch.dart';
import '../../../core/highlight/highlight_provider.dart';
import '../../../core/highlight/highlight_style.dart';

/// The assets a notification is about, by id ("1,5,9"). The list screen pages from the server, so
/// these come from the whole list (the same download the offline copy is made of) instead.
final _highlightedAssetsProvider = FutureProvider.autoDispose.family<List<AssetModel>, String>((ref, ids) async {
  final wanted = ids.split(',').toSet();
  final all = await AssetService().getAll(size: 100000);
  return all.where((a) => wanted.contains('${a.id}')).toList();
});

class AssetListScreen extends ConsumerStatefulWidget {
  const AssetListScreen({super.key});

  @override
  ConsumerState<AssetListScreen> createState() => _AssetListScreenState();
}

class _AssetListScreenState extends ConsumerState<AssetListScreen> {
  final _searchCtrl = TextEditingController();
  bool _exporting = false;
  // Bulk QR export: while choosing, the cards get tick boxes and a tap ticks instead of opening.
  bool _choosing = false;
  final Set<int> _chosen = {};
  bool _choosingAll = false;
  static const _maxQr = 1000;

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

  // Export offers the spreadsheet or the QR codes.
  Future<void> _exportMenu() async {
    final c = context.colors;
    final pick = await showModalBottomSheet<String>(
      useRootNavigator: true,
      context: context,
      showDragHandle: true,
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Export', style: TextStyle(color: c.heading, fontSize: 19, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.table_chart_outlined),
              title: const Text('Excel spreadsheet'),
              subtitle: const Text('Every asset, with all details'),
              onTap: () => Navigator.of(ctx).pop('excel'),
            ),
            ListTile(
              leading: const Icon(Icons.qr_code_2_rounded),
              title: const Text('QR codes'),
              subtitle: const Text('Choose assets, then print or save their stickers'),
              onTap: () => Navigator.of(ctx).pop('qr'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (pick == 'excel') {
      await _export();
    } else if (pick == 'qr') {
      setState(() {
        _choosing = true;
        _chosen.clear();
      });
    }
  }

  void _stopChoosing() => setState(() {
        _choosing = false;
        _chosen.clear();
      });

  // Every asset the current search and filters show, not just the loaded page.
  Future<void> _chooseAll(String search) async {
    setState(() => _choosingAll = true);
    try {
      final assets = await AssetService().getAll(
        search: search.isEmpty ? null : search,
        size: 100000,
        categoryId: ref.read(assetCategoryFilterProvider),
        officeId: ref.read(assetOfficeFilterProvider),
        condition: ref.read(assetConditionFilterProvider),
        lifecycleStatus: ref.read(assetLifecycleFilterProvider),
      );
      // assets added offline (negative id) get their QR code once they reach the server
      if (mounted) setState(() => _chosen.addAll(assets.map((a) => a.id).where((id) => id > 0)));
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.red.shade800, behavior: SnackBarBehavior.floating),
        );
      }
    } finally {
      if (mounted) setState(() => _choosingAll = false);
    }
  }

  Future<void> _exportQr() async {
    final done = await showQrExportSheet(context, _chosen.toList());
    if (done && mounted) _stopChoosing();
  }

  @override
  Widget build(BuildContext context) {
    // Adding and importing assets is ADMIN-only (web parity); staff edit their office's.
    final isAdmin = ref.watch(authProvider).valueOrNull?.isAdmin ?? false;
    final search = ref.watch(assetSearchProvider);
    final state = ref.watch(assetsPagedProvider(search));
    final countAsync = ref.watch(assetCountProvider(search));
    final filtersActive = assetFiltersActive(ref);
    // Opened from a notification: show the assets it is about, tinted, until cleared.
    final hl = highlightFor(ref, HighlightTarget.assets);

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
                      onPressed: _exporting || _choosing ? null : _exportMenu,
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
      body: hl != null ? _highlightedBody(hl) : Stack(
        children: [
          AutoRefreshTicker(
            interval: const Duration(seconds: 30),
            onTick: () => ref.read(assetsPagedProvider(search).notifier).silentRefresh(),
            // One card per asset, same as the web list (grouping was retired with the single-quantity model).
            child: PaginatedListView<AssetModel>(
              state: state,
              emptyMessage: 'No assets found.',
              // room for the choosing bar too, so the last card isn't hidden under it
              extraBottomPadding: context.mainShellBottomInset + (_choosing ? 132 : 0),
              onLoadMore: () => ref.read(assetsPagedProvider(search).notifier).loadMore(),
              onRefresh: () async {
                ref.invalidate(assetCountProvider(search));
                await ref.read(assetsPagedProvider(search).notifier).refresh();
              },
              itemBuilder: (context, asset, i) {
                final canChoose = asset.id > 0;
                final isChosen = _chosen.contains(asset.id);
                return _AssetCard(
                  asset: asset,
                  chosen: _choosing ? (canChoose ? isChosen : null) : null,
                  choosing: _choosing,
                  onTap: _choosing
                      ? (canChoose
                          ? () => setState(() => isChosen ? _chosen.remove(asset.id) : _chosen.add(asset.id))
                          : () {})
                      : () => context.push('/assets/${asset.id}'),
                );
              },
            ),
          ),
          if (_choosing)
            Positioned(
              left: 12,
              right: 12,
              bottom: context.mainShellBottomInset + 8,
              child: _ChoosingBar(
                count: _chosen.length,
                total: countAsync.valueOrNull,
                max: _maxQr,
                choosingAll: _choosingAll,
                onChooseAll: () => _chooseAll(search),
                onClear: _chosen.isEmpty ? null : () => setState(_chosen.clear),
                onCancel: _stopChoosing,
                onExport: _chosen.isEmpty || _chosen.length > _maxQr ? null : _exportQr,
              ),
            ),
        ],
      ),
    );
  }

  Widget _highlightedBody(Highlight hl) {
    final key = (hl.ids.toList()..sort()).join(',');
    final async = ref.watch(_highlightedAssetsProvider(key));
    void clear() => ref.read(highlightProvider.notifier).state = null;
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Column(children: [
        HighlightBanner(count: 0, noun: 'asset', plural: 'assets', title: hl.title, clearLabel: 'Show all', onClear: clear),
        Padding(
          padding: const EdgeInsets.all(24),
          child: Text(e is ApiException ? e.message : "Couldn't load these assets.",
              style: TextStyle(color: context.colors.textSecondary, fontSize: 15)),
        ),
      ]),
      data: (assets) => Column(
        children: [
          HighlightBanner(
            count: assets.length,
            noun: 'asset',
            plural: 'assets',
            title: hl.title,
            clearLabel: 'Show all',
            onClear: clear,
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => ref.invalidate(_highlightedAssetsProvider(key)),
              child: ListView.separated(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 24 + context.mainShellBottomInset),
                itemCount: assets.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, i) => _AssetCard(
                  asset: assets[i],
                  highlighted: true,
                  onTap: () => context.push('/assets/${assets[i].id}'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  ButtonStyle _toolbarButton(BuildContext context, {bool active = false}) =>
      toolbarButtonStyle(context, active: active);
}

class _AssetCard extends StatelessWidget {
  final AssetModel asset;
  final VoidCallback onTap;
  // While choosing assets for QR export: whether this one is ticked (null = can't be chosen
  // yet, e.g. added offline and not on the server).
  final bool choosing;
  final bool? chosen;
  /// A notification pointed to this asset.
  final bool highlighted;

  const _AssetCard({required this.asset, required this.onTap, this.choosing = false, this.chosen, this.highlighted = false});

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
        color: highlighted ? highlightTint(context) : null,
        shape: highlighted ? highlightShape() : null,
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
                          style:
                              TextStyle(color: c.textPrimary, fontSize: 16, fontWeight: FontWeight.w600, height: 1.3),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(Icons.apartment_rounded, size: 16, color: c.textTertiary),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(asset.office.officeName,
                                style: TextStyle(color: c.textSecondary, fontSize: 14),
                                overflow: TextOverflow.ellipsis),
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
                if (!choosing)
                  const DisclosureChevron()
                else if (chosen != null)
                  Checkbox(
                    value: chosen,
                    onChanged: (_) => onTap(),
                    activeColor: AppTheme.brand,
                    semanticLabel: 'Choose ${asset.propertyNumber}',
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 2417 → "2,417".
String _withCommas(int n) => n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');

/// Floats above the bottom bar while choosing assets for QR export.
class _ChoosingBar extends StatelessWidget {
  final int count;
  final int? total;
  final int max;
  final bool choosingAll;
  final VoidCallback onChooseAll;
  final VoidCallback? onClear;
  final VoidCallback onCancel;
  final VoidCallback? onExport;

  const _ChoosingBar({
    required this.count,
    required this.total,
    required this.max,
    required this.choosingAll,
    required this.onChooseAll,
    required this.onClear,
    required this.onCancel,
    required this.onExport,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final allChosen = total != null && total! > 0 && count >= total!;
    return Material(
      color: c.surface,
      elevation: 6,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Semantics(
                  liveRegion: true,
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(
                          text: _withCommas(count),
                          style: TextStyle(fontWeight: FontWeight.w700, color: c.textPrimary)),
                      const TextSpan(text: ' chosen'),
                    ]),
                    style: TextStyle(fontSize: 16, color: c.textSecondary),
                  ),
                ),
                const Spacer(),
                if (!allChosen && total != null && total! > 0)
                  TextButton(
                    onPressed: choosingAll ? null : onChooseAll,
                    child: Text(choosingAll ? 'Choosing…' : 'Choose all ${_withCommas(total!)}'),
                  ),
                if (onClear != null) TextButton(onPressed: onClear, child: const Text('Clear')),
              ],
            ),
            Text(
              count > max
                  ? 'Export at most ${_withCommas(max)} QR codes at a time.'
                  : count == 0
                      ? 'Tap the assets whose QR codes you want.'
                      : 'Tap more assets, or export now.',
              style: TextStyle(fontSize: 13, color: count > max ? Colors.red.shade700 : c.textTertiary),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: OutlinedButton(onPressed: onCancel, child: const Text('Cancel'))),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onExport,
                    icon: const Icon(Icons.qr_code_2_rounded, size: 20),
                    label: const Text('Export'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
