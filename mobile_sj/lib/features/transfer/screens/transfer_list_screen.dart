import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/asset_picker.dart';
import '../../../shared/widgets/error_state.dart';
import '../../../shared/widgets/status_badge.dart';
import '../../../shared/widgets/ui.dart';
import '../../auth/provider/auth_provider.dart';
import '../../reports/utils/formatters.dart';
import '../../dashboard/widgets/attention_card.dart';
import '../data/transfer_service.dart';
import '../model/transfer_model.dart';
import '../provider/transfer_provider.dart';

/// Transfer Asset — the web page's "Transfer requests" list. Admins see every request and
/// approve or reject the pending ones; staff see the ones they sent. "New Transfer" picks
/// an asset and opens the transfer form.
class TransferListScreen extends ConsumerStatefulWidget {
  const TransferListScreen({super.key});

  @override
  ConsumerState<TransferListScreen> createState() => _TransferListScreenState();
}

class _TransferListScreenState extends ConsumerState<TransferListScreen> {
  String? _status = 'PENDING_APPROVAL'; // what needs doing first

  Future<void> _newTransfer() async {
    final asset = await showAssetPicker(context, ref);
    if (asset == null || !mounted) return;
    await context.push<bool>('/transfers/new', extra: asset);
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = ref.watch(authProvider).value?.isAdmin ?? false;
    final async = ref.watch(transfersProvider);
    final c = context.colors;

    return Scaffold(
      appBar: AppBar(
        title: TitleWithCount(
          'Transfer Asset',
          subtitle: isAdmin ? 'Requests from staff' : 'Your transfer requests',
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton.icon(
              icon: const Icon(Icons.swap_horiz_rounded, size: 20),
              label: const Text('New Transfer'),
              style: FilledButton.styleFrom(minimumSize: const Size(0, 42), padding: const EdgeInsets.symmetric(horizontal: 14)),
              onPressed: _newTransfer,
            ),
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorState(message: e.toString(), onRetry: () => ref.invalidate(transfersProvider)),
        data: (all) {
          final items = _status == null ? all : all.where((t) => t.status == _status).toList();
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(transfersProvider),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                Text(
                  isAdmin
                      ? 'Staff transfers wait here for your approval. Transfers you make are applied right away.'
                      : 'Transfers you send wait for an administrator to approve them.',
                  style: TextStyle(color: c.textSecondary, fontSize: 15, height: 1.45),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final (value, label) in const [
                      ('PENDING_APPROVAL', 'Waiting'),
                      ('APPROVED', 'Approved'),
                      ('REJECTED', 'Rejected'),
                      (null, 'All'),
                    ])
                      ChoiceChip(
                        label: Text(
                            '$label${value == null ? '' : ' (${all.where((t) => t.status == value).length})'}'),
                        selected: _status == value,
                        onSelected: (_) => setState(() => _status = value),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                if (items.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 48),
                    child: Text(
                      all.isEmpty ? 'No transfer requests yet.' : 'No requests here.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: c.textTertiary, fontSize: 15),
                    ),
                  )
                else
                  for (final t in items) ...[
                    _TransferCard(item: t, canReview: isAdmin && t.isPending),
                    const SizedBox(height: 10),
                  ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _TransferCard extends ConsumerStatefulWidget {
  final TransferModel item;
  final bool canReview;
  const _TransferCard({required this.item, required this.canReview});

  @override
  ConsumerState<_TransferCard> createState() => _TransferCardState();
}

class _TransferCardState extends ConsumerState<_TransferCard> {
  bool _busy = false;

  Future<void> _review(Future<void> Function() action, String done) async {
    setState(() => _busy = true);
    try {
      await action();
      ref.invalidate(transfersProvider);
      ref.invalidate(attentionProvider);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message), backgroundColor: Colors.red.shade800));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reject() async {
    final note = await showDialog<String>(context: context, builder: (_) => const _RejectDialog());
    if (note == null) return;
    final t = widget.item;
    await _review(() => TransferService().reject(t.id, note), 'Rejected the transfer of ${t.propertyNumber}.');
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.item;
    final c = context.colors;
    final status = switch (t.status) {
      'PENDING_APPROVAL' => const StatusBadge(label: 'Waiting for approval', color: AppTheme.statusMaintenance),
      'APPROVED' => const StatusBadge(label: 'Approved', color: AppTheme.statusAssigned),
      _ => const StatusBadge(label: 'Rejected', color: AppTheme.statusDisposed),
    };
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/assets/${t.assetId}'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Align(alignment: Alignment.centerLeft, child: status)),
                  Text(fmtDate(t.requestedAt), style: TextStyle(color: c.textTertiary, fontSize: 14)),
                ],
              ),
              const SizedBox(height: 10),
              CodeText(t.propertyNumber),
              const SizedBox(height: 2),
              CardTitle(t.assetDescription, maxLines: 1),
              const SizedBox(height: 10),
              // from → to, spelled out
              _Move(label: 'From', value: t.fromOfficeName ?? 'Unassigned'),
              const SizedBox(height: 4),
              _Move(
                label: 'To',
                value: [t.toOfficeName, t.toLocation].whereType<String>().where((s) => s.isNotEmpty).join(' · '),
                strong: true,
              ),
              if (t.toPersonnelName != null) ...[
                const SizedBox(height: 4),
                _Move(label: 'Accountable', value: t.toPersonnelName!),
              ],
              if (t.reason != null && t.reason!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('Reason: ${t.reason}', style: TextStyle(color: c.textSecondary, fontSize: 14, height: 1.4)),
              ],
              const SizedBox(height: 8),
              MetaLine(Icons.person_rounded, 'Requested by ${t.requestedByName ?? '—'}'),
              if (!t.isPending) ...[
                const SizedBox(height: 4),
                MetaLine(Icons.how_to_reg_rounded, 'Reviewed by ${t.reviewedByName ?? '—'} · ${fmtDate(t.reviewedAt)}'),
              ],
              if (t.reviewNote != null && t.reviewNote!.isNotEmpty) ...[
                const SizedBox(height: 10),
                Callout(t.reviewNote!,
                    title: t.status == 'REJECTED' ? 'Reason for rejection' : 'Reviewer note',
                    tone: t.status == 'REJECTED' ? CalloutTone.error : CalloutTone.info),
              ],
              if (widget.canReview) ...[
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : _reject,
                        icon: const Icon(Icons.close_rounded, size: 20),
                        label: const Text('Reject'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFDC2626),
                          side: const BorderSide(color: Color(0xFFFCA5A5)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _busy
                            ? null
                            : () => _review(() => TransferService().approve(t.id),
                                'Approved — ${t.propertyNumber} moved to ${t.toOfficeName ?? 'the new office'}.'),
                        icon: _busy
                            ? const SizedBox(
                                width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.check_rounded, size: 20),
                        label: const Text('Approve'),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Move extends StatelessWidget {
  final String label;
  final String value;
  final bool strong;
  const _Move({required this.label, required this.value, this.strong = false});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 104, child: Text(label, style: TextStyle(color: c.textTertiary, fontSize: 14))),
        Expanded(
          child: Text(value,
              style: TextStyle(
                color: c.textPrimary,
                fontSize: 14,
                height: 1.35,
                fontWeight: strong ? FontWeight.w700 : FontWeight.w500,
              )),
        ),
      ],
    );
  }
}

/// Reject with an optional reason — the web's "Reason for rejecting (optional)".
class _RejectDialog extends StatefulWidget {
  const _RejectDialog();

  @override
  State<_RejectDialog> createState() => _RejectDialogState();
}

class _RejectDialogState extends State<_RejectDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Reject this transfer?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('The asset stays where it is. The person who sent it will see your reason.',
              style: TextStyle(color: context.colors.textSecondary, fontSize: 15, height: 1.45)),
          const SizedBox(height: 14),
          TextField(
            controller: _ctrl,
            autofocus: true,
            maxLines: 3,
            maxLength: 255,
            style: const TextStyle(fontSize: 16),
            decoration: const InputDecoration(labelText: 'Reason (optional)'),
          ),
        ],
      ),
      actions: [
        OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
          onPressed: () => Navigator.pop(context, _ctrl.text.trim()),
          child: const Text('Reject'),
        ),
      ],
    );
  }
}
