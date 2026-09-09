import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../model/asset_model.dart';
import '../provider/asset_provider.dart';
import '../data/asset_service.dart';
import '../provider/ai_recommendation_provider.dart';
import '../model/ai_recommendation_model.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/status_badge.dart';
import '../../../shared/widgets/delete_dialog.dart';
import '../../../shared/widgets/main_shell.dart';
import '../../auth/provider/auth_provider.dart';
import '../../asset_history/model/asset_history_model.dart';
import '../../asset_history/provider/asset_history_provider.dart';
import '../../maintenance/model/maintenance_model.dart';
import '../../maintenance/provider/maintenance_provider.dart';
import '../../disposal/model/disposal_model.dart';
import '../../disposal/provider/disposal_provider.dart';
import '../widgets/asset_qr_sheet.dart';
import '../../../shared/widgets/error_state.dart';

class AssetDetailScreen extends ConsumerWidget {
  final int assetId;
  const AssetDetailScreen({super.key, required this.assetId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assetAsync = ref.watch(assetDetailProvider(assetId));
    final isAdmin = ref.watch(authProvider).value?.isAdmin ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Asset Detail'),
        actions: [
          if (assetAsync.value != null)
            IconButton(
              icon: const Icon(Icons.qr_code_2_rounded),
              tooltip: 'Show QR code',
              onPressed: () => showAssetQrSheet(context, assetAsync.value!),
            ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () {
              ref.invalidate(assetDetailProvider(assetId));
              ref.invalidate(assetHistoryProvider(assetId));
              ref.invalidate(maintenanceByAssetProvider(assetId));
              ref.invalidate(disposalByAssetProvider(assetId));
            },
          ),
          if (isAdmin && assetAsync.value != null) ...[
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              onPressed: () async {
                final result = await context.push<bool>('/assets/$assetId/edit', extra: assetAsync.value);
                if (result == true) ref.invalidate(assetDetailProvider(assetId));
              },
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded, color: Colors.red),
              onPressed: () async {
                final reason = await showDeleteDialog(context);
                if (reason == null || !context.mounted) return;
                try {
                  await AssetService().delete(assetId, reason: reason);
                  ref.invalidate(assetsPagedProvider(ref.read(assetSearchProvider)));
                  if (context.mounted) context.pop();
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(e.toString()),
                      backgroundColor: Colors.red.shade800,
                    ));
                  }
                }
              },
            ),
          ],
        ],
      ),
      body: assetAsync.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppTheme.brand)),
        error: (err, _) => ErrorState(
          message: err.toString(),
          onRetry: () {
            ref.invalidate(assetDetailProvider(assetId));
            ref.invalidate(assetHistoryProvider(assetId));
            ref.invalidate(maintenanceByAssetProvider(assetId));
            ref.invalidate(disposalByAssetProvider(assetId));
          },
        ),
        data: (asset) => _AssetDetailBody(asset: asset),
      ),
    );
  }
}

class _AssetDetailBody extends ConsumerWidget {
  final AssetModel asset;
  const _AssetDetailBody({required this.asset});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          TabBar(
            indicatorColor: AppTheme.brand,
            labelColor: AppTheme.brand,
            unselectedLabelColor: context.colors.textSecondary,
            tabs: const [
              Tab(text: 'Details'),
              Tab(text: 'Lifecycle'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _DetailsTab(asset: asset),
                _HistoryTab(assetId: asset.id),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailsTab extends StatelessWidget {
  final AssetModel asset;
  const _DetailsTab({required this.asset});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + context.mainShellBottomInset),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(asset.propertyNumber,
                        style: const TextStyle(color: AppTheme.brand, fontSize: 13, fontWeight: FontWeight.w600)),
                    const Spacer(),
                    StatusBadge.lifecycle(asset.lifecycleStatus),
                  ],
                ),
                const SizedBox(height: 8),
                Text(asset.description,
                    style: TextStyle(color: context.colors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                StatusBadge.condition(asset.condition),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _AiRecommendationCard(assetId: asset.id),
        const SizedBox(height: 12),
        _card(context, 'Asset Details', [
          _row(context, 'Category', asset.category.categoryName),
          _row(context, 'Location', asset.office.officeName),
          if (asset.accountablePerson != null) _row(context, 'Accountable Person', asset.accountablePerson!),
          _row(context, 'Qty (Property Card)', asset.quantity.toString()),
          if (asset.physicalCount != null) ...[
            _row(context, 'Qty (Physical Count)', asset.physicalCount.toString()),
            ..._shortageOverageRows(context, asset),
          ],
        ]),
        const SizedBox(height: 12),
        _card(context, 'Financial', [
          _row(context, 'Unit Value', '₱${asset.unitValue.toStringAsFixed(2)}'),
          _row(context, 'Acquisition Date', asset.acquisitionDate),
          _row(context, 'Total Value', '₱${(asset.unitValue * asset.quantity).toStringAsFixed(2)}'),
        ]),
        if (asset.remarks != null && asset.remarks!.isNotEmpty) ...[
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionTitle(context, 'Remarks'),
                  Text(asset.remarks!, style: TextStyle(color: context.colors.textSecondary, height: 1.5)),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 12),
        _card(context, 'Record Info', [
          _row(context, 'Created', _fmt(asset.createdAt)),
          _row(context, 'Last Updated', _fmt(asset.updatedAt)),
        ]),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _card(BuildContext context, String title, List<Widget> rows) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [_sectionTitle(context, title), ...rows],
          ),
        ),
      );

  Widget _sectionTitle(BuildContext context, String t) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(t,
            style: TextStyle(color: context.colors.textTertiary, fontSize: 12,
                fontWeight: FontWeight.w600, letterSpacing: 0.8)),
      );

  Widget _row(BuildContext context, String label, String value, {Color? valueColor}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 150, child: Text(label, style: TextStyle(color: context.colors.textSecondary, fontSize: 13))),
            Expanded(
              child: Text(value,
                  style: TextStyle(
                      color: valueColor ?? context.colors.textPrimary,
                      fontSize: 13,
                      fontWeight: valueColor != null ? FontWeight.w600 : FontWeight.normal)),
            ),
          ],
        ),
      );

  // Shortage = fewer on hand than the property card says (diff < 0, red);
  // overage = more on hand than recorded (diff > 0, green) — same COA
  // reconciliation convention as the web Assets table.
  List<Widget> _shortageOverageRows(BuildContext context, AssetModel asset) {
    final diff = asset.physicalCount! - asset.quantity;
    final value = diff * asset.unitValue;
    final color = diff < 0 ? AppTheme.statusDisposed : diff > 0 ? AppTheme.brand : context.colors.textPrimary;
    final diffLabel = diff > 0 ? '+$diff' : '$diff';
    final sign = value > 0 ? '+' : value < 0 ? '-' : '';
    final valueLabel = '$sign₱${value.abs().toStringAsFixed(2)}';
    return [
      _row(context, 'Shortage/Overage Qty', diffLabel, valueColor: color),
      _row(context, 'Shortage/Overage Value', valueLabel, valueColor: color),
    ];
  }

  String _fmt(String raw) {
    try {
      final dt = DateTime.parse(raw);
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    } catch (_) {
      return raw;
    }
  }
}

class _HistoryTab extends ConsumerWidget {
  final int assetId;
  const _HistoryTab({required this.assetId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(assetHistoryProvider(assetId));
    final maintenanceAsync = ref.watch(maintenanceByAssetProvider(assetId));
    final disposalAsync = ref.watch(disposalByAssetProvider(assetId));

    if (historyAsync.isLoading) {
      return const Center(child: CircularProgressIndicator(color: AppTheme.brand));
    }
    if (historyAsync.hasError) {
      return Center(
        child: Text(historyAsync.error.toString(), style: TextStyle(color: context.colors.textTertiary)),
      );
    }

    final entries = <_LifecycleEntry>[
      ...(historyAsync.value ?? []).map(_LifecycleEntry.fromHistory),
      ...(maintenanceAsync.value ?? []).map(_LifecycleEntry.fromMaintenance),
      ...(disposalAsync.value ?? []).map(_LifecycleEntry.fromDisposal),
    ]..sort((a, b) => b.sortDate.compareTo(a.sortDate));

    return entries.isEmpty
        ? Center(child: Text('No lifecycle events recorded.', style: TextStyle(color: context.colors.textTertiary)))
        : ListView.builder(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + context.mainShellBottomInset),
            itemCount: entries.length,
            itemBuilder: (context, i) => _LifecycleTile(entry: entries[i], isLast: i == entries.length - 1),
          );
  }
}

class _LifecycleEntry {
  final String id;
  final DateTime date;
  // Distinct from [date]: what's actually used to order the merged timeline.
  // maintenanceDate/inspectionDate are date-only (no time-of-day), so same-day
  // entries always lose a naive tie-break against history's full-timestamp
  // eventDate regardless of true recency — sortDate uses updatedAt/createdAt
  // instead, which carry real time-of-day and reflect when the record was
  // actually last touched, while [date] still displays the record's own date.
  final DateTime sortDate;
  final String title;
  final Color color;
  final IconData icon;
  final String? meta;
  final String? subtitle;
  final String? note;
  final Widget? badge;
  final String? fromOffice;
  final String? toOffice;

  const _LifecycleEntry({
    required this.id,
    required this.date,
    required this.sortDate,
    required this.title,
    required this.color,
    required this.icon,
    this.meta,
    this.subtitle,
    this.note,
    this.badge,
    this.fromOffice,
    this.toOffice,
  });

  factory _LifecycleEntry.fromHistory(AssetHistoryModel h) {
    final date = DateTime.tryParse(h.eventDate) ?? DateTime.now();
    return _LifecycleEntry(
      id: 'h-${h.id}',
      date: date,
      sortDate: date,
      title: h.eventType.replaceAll('_', ' '),
      color: _historyColor(h.eventType),
      icon: _historyIcon(h.eventType),
      meta: 'by ${h.performedBy.fullName}',
      note: h.notes,
      fromOffice: h.fromOffice?.officeName,
      toOffice: h.toOffice?.officeName,
    );
  }

  factory _LifecycleEntry.fromMaintenance(MaintenanceModel m) {
    final date = DateTime.tryParse(m.maintenanceDate) ?? DateTime.now();
    final sortDate = DateTime.tryParse(m.updatedAt ?? m.createdAt) ?? date;
    return _LifecycleEntry(
      id: 'm-${m.id}',
      date: date,
      sortDate: sortDate,
      title: 'Maintenance – ${m.maintenanceType.replaceAll('_', ' ')}',
      color: AppTheme.statusMaintenance,
      icon: Icons.build_outlined,
      meta: 'by ${m.recordedBy.fullName}',
      subtitle: m.cost != null ? '₱${m.cost!.toStringAsFixed(2)}' : null,
      note: m.findings,
      badge: StatusBadge.maintenanceStatus(m.status, dense: true),
    );
  }

  factory _LifecycleEntry.fromDisposal(DisposalModel d) {
    final date = DateTime.tryParse(d.inspectionDate) ?? DateTime.now();
    final sortDate = DateTime.tryParse(d.updatedAt ?? d.createdAt) ?? date;
    return _LifecycleEntry(
      id: 'd-${d.id}',
      date: date,
      sortDate: sortDate,
      title: 'Disposal – ${d.recommendedMethod}',
      color: AppTheme.statusDisposed,
      icon: Icons.delete_outline_rounded,
      meta: 'by ${d.recordedBy.fullName}',
      subtitle: 'Inspected ${_fmtStatic(d.inspectionDate)}',
      note: d.reason,
      badge: StatusBadge.disposalStatus(d.disposalStatus, dense: true),
    );
  }

  static Color _historyColor(String eventType) => switch (eventType) {
        'REGISTERED' => Colors.grey,
        'ASSIGNED' => AppTheme.statusAssigned,
        'TRANSFERRED' => AppTheme.statusTransferred,
        'MAINTENANCE' => AppTheme.statusMaintenance,
        'DISPOSAL' => AppTheme.statusDisposed,
        'ARCHIVED' => Colors.grey.shade600,
        _ => Colors.grey,
      };

  static IconData _historyIcon(String eventType) => switch (eventType) {
        'REGISTERED' => Icons.add_circle_outline_rounded,
        'ASSIGNED' => Icons.person_add_outlined,
        'TRANSFERRED' => Icons.swap_horiz_rounded,
        'MAINTENANCE' => Icons.build_outlined,
        'DISPOSAL' => Icons.delete_outline_rounded,
        'ARCHIVED' => Icons.archive_outlined,
        _ => Icons.circle_outlined,
      };

  static String _fmtStatic(String raw) {
    try {
      final dt = DateTime.parse(raw);
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    } catch (_) {
      return raw;
    }
  }
}

class _LifecycleTile extends StatelessWidget {
  final _LifecycleEntry entry;
  final bool isLast;
  const _LifecycleTile({required this.entry, required this.isLast});

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timeline line
          Column(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: entry.color.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                  border: Border.all(color: entry.color.withValues(alpha: 0.5)),
                ),
                child: Icon(entry.icon, size: 16, color: entry.color),
              ),
              if (!isLast)
                Expanded(
                  child: Container(width: 1, color: context.colors.border, margin: const EdgeInsets.symmetric(vertical: 4)),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(entry.title,
                            style: TextStyle(color: entry.color, fontSize: 13, fontWeight: FontWeight.w600)),
                      ),
                      if (entry.badge != null) entry.badge!,
                    ],
                  ),
                  Text(_fmt(entry.date),
                      style: TextStyle(color: context.colors.textSecondary, fontSize: 12)),
                  if (entry.fromOffice != null || entry.toOffice != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (entry.fromOffice != null)
                          Text(entry.fromOffice!,
                              style: TextStyle(color: context.colors.textTertiary, fontSize: 12)),
                        if (entry.fromOffice != null && entry.toOffice != null)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            child: Icon(Icons.arrow_forward_rounded, size: 12, color: context.colors.textSecondary),
                          ),
                        if (entry.toOffice != null)
                          Text(entry.toOffice!,
                              style: TextStyle(color: context.colors.textPrimary, fontSize: 12)),
                      ],
                    ),
                  ],
                  if (entry.subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(entry.subtitle!, style: TextStyle(color: context.colors.textTertiary, fontSize: 12)),
                  ],
                  if (entry.note != null && entry.note!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(entry.note!, style: TextStyle(color: context.colors.textTertiary, fontSize: 12)),
                  ],
                  if (entry.meta != null) ...[
                    const SizedBox(height: 2),
                    Text(entry.meta!, style: TextStyle(color: context.colors.textSecondary, fontSize: 11)),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _fmt(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
}

class _AiRecommendationCard extends ConsumerStatefulWidget {
  final int assetId;
  const _AiRecommendationCard({required this.assetId});

  @override
  ConsumerState<_AiRecommendationCard> createState() => _AiRecommendationCardState();
}

class _AiRecommendationCardState extends ConsumerState<_AiRecommendationCard> {
  bool _generating = false;
  bool _autoGenerateAttempted = false;

  Future<void> _generate({bool silent = false}) async {
    setState(() => _generating = true);
    try {
      await ref.read(aiRecommendationServiceProvider).generate(widget.assetId);
      ref.invalidate(aiRecommendationProvider(widget.assetId));
    } catch (e) {
      if (mounted && !silent) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString()),
          backgroundColor: Colors.red.shade800,
        ));
      }
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Color _color(String rec) => switch (rec) {
        'MAINTAIN' => AppTheme.brand,
        'REPAIR' => AppTheme.statusMaintenance,
        'MONITOR' => AppTheme.statusAssigned,
        'REVIEW_FOR_DISPOSAL' => AppTheme.statusDisposed,
        'BUDGET_PRIORITY' => Colors.deepOrange,
        _ => Colors.grey,
      };

  String _label(String rec) => switch (rec) {
        'MAINTAIN' => 'Maintain',
        'REPAIR' => 'Repair',
        'MONITOR' => 'Monitor',
        'REVIEW_FOR_DISPOSAL' => 'Review for Disposal',
        'BUDGET_PRIORITY' => 'Budget Priority',
        _ => rec,
      };

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
    final recAsync = ref.watch(aiRecommendationProvider(widget.assetId));

    ref.listen<AsyncValue<AiRecommendationModel?>>(
      aiRecommendationProvider(widget.assetId),
      (previous, next) {
        if (isAdmin && !_generating && !_autoGenerateAttempted && next.hasValue && next.value == null) {
          _autoGenerateAttempted = true;
          _generate(silent: true);
        }
      },
    );

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
                  child: Text('AI LIFECYCLE RECOMMENDATION',
                      style: TextStyle(color: context.colors.textTertiary, fontSize: 12,
                          fontWeight: FontWeight.w600, letterSpacing: 0.8)),
                ),
                if (isAdmin)
                  _generating
                      ? const SizedBox(width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.brand))
                      : IconButton(
                          icon: Icon(Icons.refresh_rounded, size: 18, color: context.colors.textTertiary),
                          tooltip: 'Generate recommendation',
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
              child: recAsync.when(
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
              data: (rec) {
                if (rec == null) {
                  if (_generating) {
                    return Row(
                      key: const ValueKey('generating'),
                      children: [
                        const SizedBox(
                          width: 14, height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.brand),
                        ),
                        const SizedBox(width: 10),
                        Text('Generating recommendation…',
                            style: TextStyle(color: context.colors.textSecondary, fontSize: 13)),
                      ],
                    );
                  }
                  return Text(
                    key: const ValueKey('empty'),
                    isAdmin
                        ? 'No recommendation yet. Tap refresh to generate one.'
                        : 'No recommendation generated yet.',
                    style: TextStyle(color: context.colors.textSecondary, fontSize: 13),
                  );
                }
                final color = _color(rec.recommendation);
                return Column(
                  key: ValueKey('data-${rec.recommendation}-${rec.generatedAt}'),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: color.withValues(alpha: 0.4)),
                      ),
                      child: Text(_label(rec.recommendation),
                          style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(height: 10),
                    Text(rec.rationale, style: TextStyle(color: context.colors.textSecondary, fontSize: 13, height: 1.4)),
                    const SizedBox(height: 10),
                    Text('Generated ${_fmtDate(rec.generatedAt)} · advisory only, not a final decision',
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
