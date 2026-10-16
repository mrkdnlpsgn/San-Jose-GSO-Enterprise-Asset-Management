import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../model/disposal_model.dart';
import '../provider/disposal_provider.dart';
import '../provider/disposal_justification_provider.dart';
import '../data/disposal_service.dart';
import '../../../shared/widgets/delete_dialog.dart';
import '../../../shared/widgets/status_badge.dart';
import '../../../shared/widgets/approval_banner.dart';
import '../../../shared/widgets/error_state.dart';
import '../../../shared/widgets/ui.dart';
import '../../../core/theme/app_theme.dart';
import '../../reports/utils/formatters.dart';
import '../../auth/provider/auth_provider.dart';
import '../../evidence/evidence_sheet.dart';

class DisposalDetailScreen extends ConsumerWidget {
  final int disposalId;
  const DisposalDetailScreen({super.key, required this.disposalId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(disposalDetailProvider(disposalId));
    final isAdmin = ref.watch(authProvider).valueOrNull?.isAdmin ?? false;

    Future<void> delete() async {
      final reason = await showDeleteDialog(context);
      if (reason == null || !context.mounted) return;
      try {
        await DisposalService().delete(disposalId, reason: reason);
        ref.invalidate(disposalPagedProvider(ref.read(disposalSearchProvider)));
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
        title: const Text('Disposal Record'),
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
                await DisposalService().approve(disposalId);
                if (context.mounted) _afterReview(context, ref, 'Request approved.');
              },
              onReject: (note) async {
                await DisposalService().reject(disposalId, note);
                if (context.mounted) _afterReview(context, ref, 'Request rejected.');
              },
            )
          : null,
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => ErrorState(
          message: err.toString(),
          onRetry: () => ref.invalidate(disposalDetailProvider(disposalId)),
        ),
        data: (item) => _Body(
          item: item,
          // Staff can edit a record only once an admin has approved it (web parity).
          canEdit: isAdmin || item.isApproved,
          onEdit: () async {
            final result = await context.push<bool>('/disposal/$disposalId/edit', extra: item);
            if (result == true) ref.invalidate(disposalDetailProvider(disposalId));
          },
        ),
      ),
    );
  }

  void _afterReview(BuildContext context, WidgetRef ref, String message) {
    ref.invalidate(disposalDetailProvider(disposalId));
    ref.invalidate(disposalPagedProvider(ref.read(disposalSearchProvider)));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }
}

/// "DESTRUCTION" → "Destruction"
String _titleCase(String raw) => raw
    .split('_')
    .where((w) => w.isNotEmpty)
    .map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase())
    .join(' ');

class _Body extends StatelessWidget {
  final DisposalModel item;
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
                  StatusBadge.disposalStatus(item.disposalStatus),
                  StatusBadge.disposalMethod(item.recommendedMethod),
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
                          path: '/disposal/${item.id}/evidence',
                          title: 'Disposal Evidence',
                          subtitle: '${item.asset.propertyNumber} — ${item.asset.description}',
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
        DetailSection(title: 'Disposal Info', items: [
          DetailItem('Inspection Date', fmtDate(item.inspectionDate)),
          DetailItem('Method', _titleCase(item.recommendedMethod)),
          DetailItem('Status', _titleCase(item.disposalStatus)),
          DetailItem('Approved By', item.approvedBy),
          DetailItem('Appraised Value', item.appraisedValue != null ? fmtMoney(item.appraisedValue) : null),
          DetailItem('OR No.', item.orNumber),
          DetailItem('Amount', item.amount != null ? fmtMoney(item.amount) : null),
          DetailItem('Recorded By', item.recordedBy.fullName),
        ]),
        const SizedBox(height: 12),
        SectionCard(
          title: 'Reason for Disposal',
          child: Text(item.reason, style: TextStyle(color: c.textSecondary, fontSize: 15, height: 1.5)),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: 'Inspection Findings',
          child: Text(item.inspectionFindings, style: TextStyle(color: c.textSecondary, fontSize: 15, height: 1.5)),
        ),
        const SizedBox(height: 12),
        _AiJustificationCard(disposalId: item.id),
      ],
    );
  }
}

class _AiJustificationCard extends ConsumerStatefulWidget {
  final int disposalId;
  const _AiJustificationCard({required this.disposalId});

  @override
  ConsumerState<_AiJustificationCard> createState() => _AiJustificationCardState();
}

class _AiJustificationCardState extends ConsumerState<_AiJustificationCard> {
  bool _generating = false;

  Future<void> _generate() async {
    setState(() => _generating = true);
    try {
      await ref.read(disposalJustificationServiceProvider).generate(widget.disposalId);
      ref.invalidate(disposalJustificationProvider(widget.disposalId));
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
    final justAsync = ref.watch(disposalJustificationProvider(widget.disposalId));
    final c = context.colors;

    return SectionCard(
      title: 'AI Disposal Justification',
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
        child: justAsync.when(
          loading: () => const Padding(
            key: ValueKey('loading'),
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) =>
              Text(key: const ValueKey('error'), e.toString(), style: TextStyle(color: c.textSecondary, fontSize: 14)),
          data: (just) {
            if (just == null) {
              return Text(
                key: const ValueKey('empty'),
                isAdmin
                    ? 'No justification drafted yet. New records get one automatically — tap Generate to draft one now.'
                    : 'No justification drafted yet.',
                style: TextStyle(color: c.textSecondary, fontSize: 15, height: 1.45),
              );
            }
            return Column(
              key: ValueKey('data-${just.generatedAt}'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(just.justification, style: TextStyle(color: c.textSecondary, fontSize: 15, height: 1.5)),
                const SizedBox(height: 10),
                Text('Generated ${fmtDate(just.generatedAt)} · draft for review, not a final decision',
                    style: TextStyle(color: c.textTertiary, fontSize: 13)),
              ],
            );
          },
        ),
      ),
    );
  }
}
