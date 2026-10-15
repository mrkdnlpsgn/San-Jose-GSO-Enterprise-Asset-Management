import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/assets/model/asset_model.dart';
import '../../features/assets/provider/asset_provider.dart';
import '../../core/theme/app_theme.dart';
import 'app_search_field.dart';

Future<AssetModel?> showAssetPicker(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<AssetModel>(
    useRootNavigator: true, // above the bottom bar, not behind it
    context: context,
    isScrollControlled: true,
    backgroundColor: context.colors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => _AssetPickerSheet(ref: ref),
  );
}

class _AssetPickerSheet extends ConsumerStatefulWidget {
  final WidgetRef ref;
  const _AssetPickerSheet({required this.ref});

  @override
  ConsumerState<_AssetPickerSheet> createState() => _AssetPickerSheetState();
}

class _AssetPickerSheetState extends ConsumerState<_AssetPickerSheet> {
  final _ctrl = TextEditingController();
  // Deliberately local, not assetSearchProvider — sharing that provider with
  // the main Asset List screen meant typing here overwrote the search box
  // behind this sheet, and picking an asset cleared it too.
  String _search = '';

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(assetsPagedProvider(_search));

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      expand: false,
      builder: (_, scrollCtrl) => Column(
        children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            width: 40, height: 4,
            decoration: BoxDecoration(color: context.colors.textTertiary, borderRadius: BorderRadius.circular(2)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: AppSearchField(
              controller: _ctrl,
              autofocus: true,
              hintText: 'Search assets...',
              onChanged: (v) => setState(() => _search = v),
            ),
          ),
          Expanded(
            child: state.isLoading
                ? const Center(child: CircularProgressIndicator())
                : state.error != null && state.items.isEmpty
                    ? Center(child: Text(state.error.toString(), style: TextStyle(color: context.colors.textTertiary)))
                    : NotificationListener<ScrollNotification>(
                        onNotification: (notification) {
                          if (notification.metrics.pixels >= notification.metrics.maxScrollExtent - 200) {
                            ref.read(assetsPagedProvider(_search).notifier).loadMore();
                          }
                          return false;
                        },
                        child: ListView.builder(
                          controller: scrollCtrl,
                          itemCount: state.items.length + (state.hasMore ? 1 : 0),
                          itemBuilder: (_, i) {
                            if (i >= state.items.length) {
                              return const Padding(
                                padding: EdgeInsets.symmetric(vertical: 16),
                                child: Center(
                                  child: SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  ),
                                ),
                              );
                            }
                            final asset = state.items[i];
                            return ListTile(
                              title: Text(asset.description, style: TextStyle(color: context.colors.textPrimary, fontSize: 14)),
                              subtitle: Text(asset.propertyNumber, style: TextStyle(color: context.brandAccent, fontSize: 14)),
                              onTap: () => Navigator.pop(context, asset),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}
