import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/status_badge.dart';
import '../provider/disposal_provider.dart';

const _methods = ['SALE', 'TRANSFER', 'DESTRUCTION', 'OTHERS'];
const _statuses = ['PENDING', 'APPROVED', 'COMPLETED'];

bool disposalFiltersActive(WidgetRef ref) =>
    ref.watch(disposalMethodFilterProvider) != null || ref.watch(disposalStatusFilterProvider) != null;

Future<void> showDisposalFilterSheet(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: context.colors.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => const _DisposalFilterSheet(),
  );
}

class _DisposalFilterSheet extends ConsumerWidget {
  const _DisposalFilterSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final method = ref.watch(disposalMethodFilterProvider);
    final status = ref.watch(disposalStatusFilterProvider);

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 4, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Filter Disposal',
                  style: TextStyle(color: context.colors.textPrimary, fontSize: 16, fontWeight: FontWeight.w600)),
              const Spacer(),
              TextButton(
                onPressed: () {
                  ref.read(disposalMethodFilterProvider.notifier).state = null;
                  ref.read(disposalStatusFilterProvider.notifier).state = null;
                },
                child: const Text('Clear all'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text('Method', style: TextStyle(color: context.colors.textTertiary, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          DropdownButtonFormField<String?>(
            initialValue: method,
            isExpanded: true,
            decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
            items: [
              const DropdownMenuItem(value: null, child: Text('All methods')),
              ..._methods.map((m) => DropdownMenuItem(value: m, child: Text(StatusBadge.disposalMethod(m).label))),
            ],
            onChanged: (v) => ref.read(disposalMethodFilterProvider.notifier).state = v,
          ),
          const SizedBox(height: 14),
          Text('Status', style: TextStyle(color: context.colors.textTertiary, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          DropdownButtonFormField<String?>(
            initialValue: status,
            isExpanded: true,
            decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
            items: [
              const DropdownMenuItem(value: null, child: Text('All statuses')),
              ..._statuses.map((s) => DropdownMenuItem(value: s, child: Text(StatusBadge.disposalStatus(s).label))),
            ],
            onChanged: (v) => ref.read(disposalStatusFilterProvider.notifier).state = v,
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
