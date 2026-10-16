import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/provider/reference_provider.dart';
import '../../../shared/widgets/status_badge.dart';
import '../provider/asset_provider.dart';
import '../../../shared/widgets/ios_pickers.dart';

const _conditions = ['SERVICEABLE', 'REPAIRABLE', 'UNSERVICEABLE'];
const _lifecycleStatuses = ['REGISTERED', 'ASSIGNED', 'TRANSFERRED', 'UNDER_MAINTENANCE', 'DISPOSED', 'ARCHIVED'];

/// True if any asset filter is currently active — used to badge the filter icon.
bool assetFiltersActive(WidgetRef ref) =>
    ref.watch(assetCategoryFilterProvider) != null ||
    ref.watch(assetOfficeFilterProvider) != null ||
    ref.watch(assetConditionFilterProvider) != null ||
    ref.watch(assetLifecycleFilterProvider) != null;

Future<void> showAssetFilterSheet(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet(
    useRootNavigator: true, // above the bottom bar, not behind it
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: context.colors.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => const _AssetFilterSheet(),
  );
}

class _AssetFilterSheet extends ConsumerWidget {
  const _AssetFilterSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(categoriesProvider);
    final officesAsync = ref.watch(officesProvider);
    final categoryId = ref.watch(assetCategoryFilterProvider);
    final officeId = ref.watch(assetOfficeFilterProvider);
    final condition = ref.watch(assetConditionFilterProvider);
    final lifecycleStatus = ref.watch(assetLifecycleFilterProvider);

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 4, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Filter Assets',
                  style: TextStyle(color: context.colors.textPrimary, fontSize: 16, fontWeight: FontWeight.w600)),
              const Spacer(),
              TextButton(
                onPressed: () {
                  ref.read(assetCategoryFilterProvider.notifier).state = null;
                  ref.read(assetOfficeFilterProvider.notifier).state = null;
                  ref.read(assetConditionFilterProvider.notifier).state = null;
                  ref.read(assetLifecycleFilterProvider.notifier).state = null;
                },
                child: const Text('Clear all'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          categoriesAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
            data: (categories) => _dropdown<int?>(
              context,
              label: 'Category',
              value: categoryId,
              items: [
                const DropdownMenuItem(value: null, child: Text('All categories')),
                ...categories.map((c) => DropdownMenuItem(value: c.id, child: Text(c.categoryName))),
              ],
              onChanged: (v) => ref.read(assetCategoryFilterProvider.notifier).state = v,
            ),
          ),
          const SizedBox(height: 14),
          officesAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
            data: (offices) => _dropdown<int?>(
              context,
              label: 'Office',
              value: officeId,
              items: [
                const DropdownMenuItem(value: null, child: Text('All offices')),
                ...offices.map((o) => DropdownMenuItem(value: o.id, child: Text(o.officeName))),
              ],
              onChanged: (v) => ref.read(assetOfficeFilterProvider.notifier).state = v,
            ),
          ),
          const SizedBox(height: 14),
          _dropdown<String?>(
            context,
            label: 'Condition',
            value: condition,
            items: [
              const DropdownMenuItem(value: null, child: Text('All conditions')),
              ..._conditions.map((c) => DropdownMenuItem(value: c, child: Text(StatusBadge.condition(c).label))),
            ],
            onChanged: (v) => ref.read(assetConditionFilterProvider.notifier).state = v,
          ),
          const SizedBox(height: 14),
          _dropdown<String?>(
            context,
            label: 'Lifecycle Status',
            value: lifecycleStatus,
            items: [
              const DropdownMenuItem(value: null, child: Text('All statuses')),
              ..._lifecycleStatuses.map((l) => DropdownMenuItem(value: l, child: Text(StatusBadge.lifecycle(l).label))),
            ],
            onChanged: (v) => ref.read(assetLifecycleFilterProvider.notifier).state = v,
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dropdown<T>(
    BuildContext context, {
    required String label,
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(color: context.colors.textTertiary, fontSize: 14, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        IosSelectFormField<T>(
          initialValue: value,
          items: items,
          onChanged: onChanged,
          isExpanded: true,
          decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
        ),
      ],
    );
  }
}
