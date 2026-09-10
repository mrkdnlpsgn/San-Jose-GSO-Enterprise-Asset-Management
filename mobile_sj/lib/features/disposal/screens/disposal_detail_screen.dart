import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../model/disposal_model.dart';
import '../provider/disposal_provider.dart';
import '../provider/disposal_justification_provider.dart';
import '../data/disposal_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/delete_dialog.dart';
import '../../../shared/widgets/status_badge.dart';
import '../../../shared/widgets/error_state.dart';
import '../../auth/provider/auth_provider.dart';

class DisposalDetailScreen extends ConsumerWidget {
  final int disposalId;
  const DisposalDetailScreen({super.key, required this.disposalId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(disposalDetailProvider(disposalId));
    final isAdmin = ref.watch(authProvider).value?.isAdmin ?? false;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Disposal Detail'),
        actions: [
          if (isAdmin && async.value != null) ...[
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              onPressed: () async {
                final result = await context.push<bool>('/disposal/$disposalId/edit', extra: async.value);
                if (result == true) ref.invalidate(disposalDetailProvider(disposalId));
              },
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded, color: Colors.red),
              onPressed: () async {
                final reason = await showDeleteDialog(context);
                if (reason == null || !context.mounted) return;
                try {
                  await DisposalService().delete(disposalId, reason: reason);
                  ref.invalidate(disposalPagedProvider(ref.read(disposalSearchProvider)));
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
          onRetry: () => ref.invalidate(disposalDetailProvider(disposalId)),
        ),
        data: (item) => _Body(item: item),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  final DisposalModel item;
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
                    StatusBadge.disposalMethod(item.recommendedMethod),
                    const SizedBox(width: 8),
                    StatusBadge.disposalStatus(item.disposalStatus),
                  ],
                ),
                const SizedBox(height: 10),
                Text(item.asset.description,
                    style: TextStyle(color: context.colors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(item.asset.propertyNumber, style: const TextStyle(color: AppTheme.brand, fontSize: 13)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _card(context, 'Disposal Info', [
          _row(context, 'Inspection Date', item.inspectionDate),
          _row(context, 'Method', item.recommendedMethod),
          _row(context, 'Status', item.disposalStatus),
          if (item.approvedBy != null) _row(context, 'Approved By', item.approvedBy!),
          if (item.appraisedValue != null) _row(context, 'Appraised Value', '₱${item.appraisedValue!.toStringAsFixed(2)}'),
          if (item.orNumber != null) _row(context, 'OR No.', item.orNumber!),
          if (item.amount != null) _row(context, 'Amount', '₱${item.amount!.toStringAsFixed(2)}'),
          _row(context, 'Recorded By', item.recordedBy.fullName),
        ]),
        const SizedBox(height: 12),
        _card(context, 'Depreciation (Informational)', [
          _row(context, 'Unit Cost', '₱${item.asset.unitValue.toStringAsFixed(2)}'),
          _row(context, 'Accumulated Depreciation',
              item.accumulatedDepreciation != null ? '₱${item.accumulatedDepreciation!.toStringAsFixed(2)}' : '—'),
          _row(context, 'Carrying Amount',
              item.carryingAmount != null ? '₱${item.carryingAmount!.toStringAsFixed(2)}' : '—'),
        ]),
        const SizedBox(height: 12),
        _card(context, 'Reason for Disposal', [], body: item.reason),
        const SizedBox(height: 12),
        _card(context, 'Inspection Findings', [], body: item.inspectionFindings),
        const SizedBox(height: 12),
        _AiJustificationCard(disposalId: item.id),
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
                  style: TextStyle(color: context.colors.textTertiary, fontSize: 12,
                      fontWeight: FontWeight.w600, letterSpacing: 0.8)),
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
    final justAsync = ref.watch(disposalJustificationProvider(widget.disposalId));

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
                  child: Text('AI DISPOSAL JUSTIFICATION',
                      style: TextStyle(color: context.colors.textTertiary, fontSize: 12,
                          fontWeight: FontWeight.w600, letterSpacing: 0.8)),
                ),
                if (isAdmin)
                  _generating
                      ? const SizedBox(width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.brand))
                      : IconButton(
                          icon: Icon(Icons.refresh_rounded, size: 18, color: context.colors.textTertiary),
                          tooltip: 'Generate justification',
                          onPressed: _generate,
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
              ],
            ),
            const SizedBox(height: 12),
            justAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Center(child: CircularProgressIndicator(color: AppTheme.brand)),
              ),
              error: (e, _) => Text(e.toString(), style: TextStyle(color: context.colors.textSecondary, fontSize: 12)),
              data: (just) {
                if (just == null) {
                  return Text(
                    isAdmin
                        ? 'No justification drafted yet. Tap refresh to generate one.'
                        : 'No justification drafted yet.',
                    style: TextStyle(color: context.colors.textSecondary, fontSize: 13),
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(just.justification,
                        style: TextStyle(color: context.colors.textSecondary, fontSize: 13, height: 1.5)),
                    const SizedBox(height: 10),
                    Text('Generated ${_fmtDate(just.generatedAt)} · draft for review, not a final decision',
                        style: TextStyle(color: context.colors.textSecondary, fontSize: 11)),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
