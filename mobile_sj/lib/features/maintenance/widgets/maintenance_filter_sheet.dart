import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/status_badge.dart';
import '../provider/maintenance_provider.dart';

const _types = ['PREVENTIVE', 'CORRECTIVE', 'REPAIR'];
const _statuses = ['COMPLETED', 'ONGOING', 'SCHEDULED'];

bool maintenanceFiltersActive(WidgetRef ref) =>
    ref.watch(maintenanceTypeFilterProvider) != null || ref.watch(maintenanceStatusFilterProvider) != null;

Future<void> showMaintenanceFilterSheet(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet(
    useRootNavigator: true, // above the bottom bar, not behind it
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: context.colors.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => const _MaintenanceFilterSheet(),
  );
}

class _MaintenanceFilterSheet extends ConsumerWidget {
  const _MaintenanceFilterSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final type = ref.watch(maintenanceTypeFilterProvider);
    final status = ref.watch(maintenanceStatusFilterProvider);

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 4, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Filter Maintenance',
                  style: TextStyle(color: context.colors.textPrimary, fontSize: 16, fontWeight: FontWeight.w600)),
              const Spacer(),
              TextButton(
                onPressed: () {
                  ref.read(maintenanceTypeFilterProvider.notifier).state = null;
                  ref.read(maintenanceStatusFilterProvider.notifier).state = null;
                },
                child: const Text('Clear all'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text('Type', style: TextStyle(color: context.colors.textTertiary, fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          DropdownButtonFormField<String?>(
            initialValue: type,
            isExpanded: true,
            decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
            items: [
              const DropdownMenuItem(value: null, child: Text('All types')),
              ..._types.map((t) => DropdownMenuItem(value: t, child: Text(StatusBadge.maintenanceType(t).label))),
            ],
            onChanged: (v) => ref.read(maintenanceTypeFilterProvider.notifier).state = v,
          ),
          const SizedBox(height: 14),
          Text('Status', style: TextStyle(color: context.colors.textTertiary, fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          DropdownButtonFormField<String?>(
            initialValue: status,
            isExpanded: true,
            decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
            items: [
              const DropdownMenuItem(value: null, child: Text('All statuses')),
              ..._statuses.map((s) => DropdownMenuItem(value: s, child: Text(StatusBadge.maintenanceStatus(s).label))),
            ],
            onChanged: (v) => ref.read(maintenanceStatusFilterProvider.notifier).state = v,
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
}
