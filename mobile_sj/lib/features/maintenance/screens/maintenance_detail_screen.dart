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
import '../../../shared/widgets/approval_banner.dart';
import '../../../shared/widgets/error_state.dart';
import '../../../shared/widgets/ui.dart';
import '../../reports/utils/formatters.dart';
import '../../auth/provider/auth_provider.dart';
import '../../evidence/evidence_sheet.dart';

class MaintenanceDetailScreen extends ConsumerWidget {
  final int maintenanceId;
  const MaintenanceDetailScreen({super.key, required this.maintenanceId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(maintenanceDetailProvider(maintenanceId));
    final isAdmin = ref.watch(authProvider).valueOrNull?.isAdmin ?? false;

    Future<void> delete() async {
      final reason = await showDeleteDialog(context);
      if (reason == null || !context.mounted) return;
      try {
        await MaintenanceService().delete(maintenanceId, reason: reason);
        ref.invalidate(maintenancePagedProvider(ref.read(maintenanceSearchProvider)));
        if (context.mounted) context.pop();
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: Colors.red.shade800));
        }
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Maintenance Record'),
        actions: [
          if (isAdmin && async.valueOrNull != null)
            PopupMenuButton<String>(
              tooltip: 'More actions',
              onSelected: (v) {
                if (v == 'delete') delete();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'delete',
                  child: ListTile(
                    leading: Icon(Icons.delete_outline_rounded, color: Color(0xFFDC2626)),
                    title: Text('Delete record', style: TextStyle(color: Color(0xFFDC2626))),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
        ],
      ),
      // Admin reviewing a staff request: approving applies it to the asset.
      bottomNavigationBar: isAdmin && async.valueOrNull?.approvalStatus == 'PENDING_APPROVAL'
          ? ApprovalActionsBar(
              onApprove: () async {
                await MaintenanceService().approve(maintenanceId);
                if (context.mounted) _afterReview(context, ref, 'Request approved.');
              },
              onReject: (note) async {
                await MaintenanceService().reject(maintenanceId, note);
                if (context.mounted) _afterReview(context, ref, 'Request rejected.');
              },
            )
          : null,
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => ErrorState(
          message: err.toString(),
          onRetry: () => ref.invalidate(maintenanceDetailProvider(maintenanceId)),
        ),
        data: (item) => _Body(
          item: item,
          // Staff can edit a record only once an admin has approved it (web parity).
          canEdit: isAdmin || item.isApproved,
          onEdit: () async {
            final result = await context.push<bool>('/maintenance/$maintenanceId/edit', extra: item);
            if (result == true) ref.invalidate(maintenanceDetailProvider(maintenanceId));
          },
        ),
      ),
    );
  }

  void _afterReview(BuildContext context, WidgetRef ref, String message) {
    ref.invalidate(maintenanceDetailProvider(maintenanceId));
    ref.invalidate(maintenancePagedProvider(ref.read(maintenanceSearchProvider)));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }
}

class _Body extends StatelessWidget {
  final MaintenanceModel item;
  final bool canEdit;
  final VoidCallback onEdit;
  const _Body({required this.item, required this.canEdit, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        ApprovalBanner(
          approvalStatus: item.approvalStatus,
          requestedByName: item.requestedByName,
          reviewNote: item.reviewNote,
        ),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CodeText(item.asset.propertyAndPar, size: 14),
                const SizedBox(height: 4),
                Text(item.asset.description,
                    style: TextStyle(color: c.heading, fontSize: 21, height: 1.25, fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  StatusBadge.maintenanceStatus(item.status),
                  StatusBadge.maintenanceType(item.maintenanceType),
                ]),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.photo_camera_outlined, size: 20),
                        label: const Text('Photos'),
                        onPressed: () => showEvidenceSheet(
                          context,
                          path: '/maintenance/${item.id}/photos',
                          title: 'Inspection Evidence',
                          subtitle: '${item.asset.propertyNumber}: ${item.asset.description}',
                        ),
                      ),
                    ),
                    if (canEdit) ...[
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.icon(
                          icon: const Icon(Icons.edit_rounded, size: 20),
                          label: const Text('Edit'),
                          onPressed: onEdit,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        DetailSection(title: 'Maintenance Info', items: [
          DetailItem('Date', fmtDate(item.maintenanceDate)),
          DetailItem('Assigned To', item.assignedTo),
          DetailItem('Cost', item.cost != null ? fmtMoney(item.cost) : null),
          DetailItem('Recorded By', item.recordedBy.fullName),
        ]),
        const SizedBox(height: 12),
        SectionCard(
          title: 'Findings',
          child: Text(item.findings, style: TextStyle(color: c.textSecondary, fontSize: 15, height: 1.5)),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: 'Actions Taken',
          child: Text(item.actionsTaken, style: TextStyle(color: c.textSecondary, fontSize: 15, height: 1.5)),
        ),
        const SizedBox(height: 12),
        _AiSummaryCard(maintenanceId: item.id),
      ],
    );
  }
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

  @override
  Widget build(BuildContext context) {
    final isAdmin = ref.watch(authProvider).valueOrNull?.isAdmin ?? false;
    final summaryAsync = ref.watch(maintenanceSummaryProvider(widget.maintenanceId));
    final c = context.colors;

    return SectionCard(
      title: 'AI Summary',
      trailing: !isAdmin
          ? null
          : _generating
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                )
              : TextButton(onPressed: _generate, child: const Text('Generate')),
      child: AnimatedSwitcher(
        duration: AppTheme.motionMedium,
        switchInCurve: AppTheme.motionCurve,
        switchOutCurve: AppTheme.motionCurve,
        child: summaryAsync.when(
          loading: () => const Padding(
            key: ValueKey('loading'),
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Text(
            key: const ValueKey('error'),
            e.toString(),
            style: TextStyle(color: c.textSecondary, fontSize: 14),
          ),
          data: (summary) {
            if (summary == null) {
              return Text(
                key: const ValueKey('empty'),
                isAdmin
                    ? 'No summary yet. New records get one automatically. Tap Generate to write one now.'
                    : 'No summary generated yet.',
                style: TextStyle(color: c.textSecondary, fontSize: 15, height: 1.45),
              );
            }
            return Column(
              key: ValueKey('data-${summary.generatedAt}'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(summary.summary, style: TextStyle(color: c.textSecondary, fontSize: 15, height: 1.5)),
                const SizedBox(height: 10),
                Text('Generated ${fmtDate(summary.generatedAt)} · draft for review, not a final decision',
                    style: TextStyle(color: c.textTertiary, fontSize: 13)),
              ],
            );
          },
        ),
      ),
    );
  }
}
