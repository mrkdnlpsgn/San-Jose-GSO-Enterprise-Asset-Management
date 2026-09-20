import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../model/maintenance_model.dart';
import '../provider/maintenance_provider.dart';
import '../provider/maintenance_summary_provider.dart';
import '../data/maintenance_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/delete_dialog.dart';
import '../../../shared/widgets/status_badge.dart';
import '../../../shared/widgets/error_state.dart';
import '../../auth/provider/auth_provider.dart';
import '../../evidence/evidence_sheet.dart';

class MaintenanceDetailScreen extends ConsumerWidget {
  final int maintenanceId;
  const MaintenanceDetailScreen({super.key, required this.maintenanceId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(maintenanceDetailProvider(maintenanceId));
    final isAdmin = ref.watch(authProvider).value?.isAdmin ?? false;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Maintenance Detail'),
        actions: [
          if (async.value != null)
            IconButton(
              icon: const Icon(Icons.photo_camera_outlined),
              tooltip: 'Evidence photos',
              onPressed: () => showEvidenceSheet(
                context,
                path: '/maintenance/$maintenanceId/photos',
                title: 'Inspection Evidence',
                subtitle: '${async.value!.asset.propertyNumber} — ${async.value!.asset.description}',
              ),
            ),
          if (isAdmin && async.value != null) ...[
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              onPressed: () async {
                final result = await context.push<bool>('/maintenance/$maintenanceId/edit', extra: async.value);
                if (result == true) ref.invalidate(maintenanceDetailProvider(maintenanceId));
              },
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded, color: Colors.red),
              onPressed: () async {
                final reason = await showDeleteDialog(context);
                if (reason == null || !context.mounted) return;
                try {
                  await MaintenanceService().delete(maintenanceId, reason: reason);
                  ref.invalidate(maintenancePagedProvider(ref.read(maintenanceSearchProvider)));
                  if (context.mounted) context.pop();
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(e.toString()), backgroundColor: Colors.red.shade800));
                  }
                }
              },
            ),
          ],
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppTheme.brand)),
        error: (err, _) => ErrorState(
          message: err.toString(),
          onRetry: () => ref.invalidate(maintenanceDetailProvider(maintenanceId)),
        ),
        data: (item) => _Body(item: item),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  final MaintenanceModel item;
  const _Body({required this.item});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    StatusBadge.maintenanceType(item.maintenanceType),
                    const SizedBox(width: 8),
                    StatusBadge.maintenanceStatus(item.status),
                  ],
                ),
                const SizedBox(height: 10),
                Text(item.asset.description,
                    style: TextStyle(color: context.colors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(item.asset.propertyAndPar,
                    style: const TextStyle(color: AppTheme.brand, fontSize: 13)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _card(context, 'Maintenance Info', [
          _row(context, 'Date', item.maintenanceDate),
          if (item.assignedTo != null) _row(context, 'Assigned To', item.assignedTo!),
          if (item.cost != null) _row(context, 'Cost', '₱${item.cost!.toStringAsFixed(2)}'),
          _row(context, 'Recorded By', item.recordedBy.fullName),
        ]),
        const SizedBox(height: 12),
        _card(context, 'Findings', [], body: item.findings),
        const SizedBox(height: 12),
        _card(context, 'Actions Taken', [], body: item.actionsTaken),
        const SizedBox(height: 12),
        _AiSummaryCard(maintenanceId: item.id),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _card(BuildContext context, String title, List<Widget> rows, {String? body}) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: TextStyle(
                      color: context.colors.textTertiary, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.8)),
              const SizedBox(height: 12),
              if (body != null)
                Text(body, style: TextStyle(color: context.colors.textSecondary, height: 1.5))
              else
                ...rows,
            ],
          ),
        ),
      );

  Widget _row(BuildContext context, String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 140, child: Text(label, style: TextStyle(color: context.colors.textSecondary, fontSize: 13))),
            Expanded(child: Text(value, style: TextStyle(color: context.colors.textPrimary, fontSize: 13))),
          ],
        ),
      );
}

class _AiSummaryCard extends ConsumerStatefulWidget {
  final int maintenanceId;
  const _AiSummaryCard({required this.maintenanceId});

  @override
  ConsumerState<_AiSummaryCard> createState() => _AiSummaryCardState();
}

class _AiSummaryCardState extends ConsumerState<_AiSummaryCard> {
  bool _generating = false;

  Future<void> _generate() async {
    setState(() => _generating = true);
    try {
      await ref.read(maintenanceSummaryServiceProvider).generate(widget.maintenanceId);
      ref.invalidate(maintenanceSummaryProvider(widget.maintenanceId));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString()),
          backgroundColor: Colors.red.shade800,
        ));
      }
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  String _fmtDate(String raw) {
    try {
      final dt = DateTime.parse(raw);
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    } catch (_) {
      return raw;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = ref.watch(authProvider).value?.isAdmin ?? false;
    final summaryAsync = ref.watch(maintenanceSummaryProvider(widget.maintenanceId));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.auto_awesome_rounded, size: 16, color: AppTheme.brand),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('AI SUMMARY',
                      style: TextStyle(color: context.colors.textTertiary, fontSize: 12,
                          fontWeight: FontWeight.w600, letterSpacing: 0.8)),
                ),
                if (isAdmin)
                  _generating
                      ? const SizedBox(width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.brand))
                      : IconButton(
                          icon: Icon(Icons.refresh_rounded, size: 18, color: context.colors.textTertiary),
                          tooltip: 'Generate summary',
                          onPressed: _generate,
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
              ],
            ),
            const SizedBox(height: 12),
            AnimatedSwitcher(
              duration: AppTheme.motionMedium,
              switchInCurve: AppTheme.motionCurve,
              switchOutCurve: AppTheme.motionCurve,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SizeTransition(sizeFactor: animation, alignment: Alignment.topCenter, child: child),
              ),
              child: summaryAsync.when(
              loading: () => const Padding(
                key: ValueKey('loading'),
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Center(child: CircularProgressIndicator(color: AppTheme.brand)),
              ),
              error: (e, _) => Text(
                key: const ValueKey('error'),
                e.toString(),
                style: TextStyle(color: context.colors.textSecondary, fontSize: 12),
              ),
              data: (summary) {
                if (summary == null) {
                  return Text(
                    key: const ValueKey('empty'),
                    isAdmin ? 'No summary yet. Tap refresh to generate one.' : 'No summary generated yet.',
                    style: TextStyle(color: context.colors.textSecondary, fontSize: 13),
                  );
                }
                return Column(
                  key: ValueKey('data-${summary.generatedAt}'),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(summary.summary,
                        style: TextStyle(color: context.colors.textSecondary, fontSize: 13, height: 1.5)),
                    const SizedBox(height: 10),
                    Text('Generated ${_fmtDate(summary.generatedAt)} · draft for review, not a final decision',
                        style: TextStyle(color: context.colors.textSecondary, fontSize: 11)),
                  ],
                );
              },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
