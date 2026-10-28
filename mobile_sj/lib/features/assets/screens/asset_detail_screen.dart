import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../model/asset_model.dart';
import '../data/return_papers_service.dart';
import '../widgets/return_papers_card.dart';
import '../provider/asset_provider.dart';
import '../data/asset_service.dart';
import '../provider/ai_recommendation_provider.dart';
import '../model/ai_recommendation_model.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/status_badge.dart';
import '../../../shared/widgets/section_card.dart';
import '../../reports/utils/formatters.dart';
import '../../../shared/widgets/delete_dialog.dart';
import '../../auth/provider/auth_provider.dart';
import '../../asset_history/model/asset_history_model.dart';
import '../../asset_history/provider/asset_history_provider.dart';
import '../../maintenance/model/maintenance_model.dart';
import '../../maintenance/provider/maintenance_provider.dart';
import '../../disposal/model/disposal_model.dart';
import '../../disposal/provider/disposal_provider.dart';
import '../widgets/asset_qr_sheet.dart';
import '../../evidence/evidence_sheet.dart';
import '../../../shared/widgets/error_state.dart';

class AssetDetailScreen extends ConsumerWidget {
  final int assetId;
  const AssetDetailScreen({super.key, required this.assetId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assetAsync = ref.watch(assetDetailProvider(assetId));
    final isAdmin = ref.watch(authProvider).valueOrNull?.isAdmin ?? false;

    void refresh() {
      ref.invalidate(assetDetailProvider(assetId));
      ref.invalidate(assetHistoryProvider(assetId));
      ref.invalidate(maintenanceByAssetProvider(assetId));
      ref.invalidate(disposalByAssetProvider(assetId));
      ref.invalidate(returnPapersProvider(assetId));
    }

    Future<void> delete() async {
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
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Asset Details'),
        actions: [
          // QR, photos and edit are worded buttons on the page itself; the rarer actions live here.
          PopupMenuButton<String>(
            tooltip: 'More actions',
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (v) {
              if (v == 'refresh') refresh();
              if (v == 'delete') delete();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'refresh',
                child: ListTile(leading: Icon(Icons.refresh_rounded), title: Text('Refresh'), contentPadding: EdgeInsets.zero),
              ),
              if (isAdmin && assetAsync.valueOrNull != null)
                const PopupMenuItem(
                  value: 'delete',
                  child: ListTile(
                    leading: Icon(Icons.delete_outline_rounded, color: Color(0xFFDC2626)),
                    title: Text('Delete asset', style: TextStyle(color: Color(0xFFDC2626))),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
            ],
          ),
        ],
      ),
      body: assetAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => ErrorState(message: err.toString(), onRetry: refresh),
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
          Container(
            decoration: BoxDecoration(
              color: context.colors.surface,
              border: Border(bottom: BorderSide(color: context.colors.border)),
            ),
            child: TabBar(
              indicatorColor: context.brandAccent,
              indicatorWeight: 3,
              indicatorSize: TabBarIndicatorSize.tab,
              dividerHeight: 0,
              labelColor: context.brandAccent,
              unselectedLabelColor: context.colors.textSecondary,
              labelStyle: const TextStyle(fontFamily: AppTheme.fontFamily, fontSize: 16, fontWeight: FontWeight.w700),
              unselectedLabelStyle: const TextStyle(fontFamily: AppTheme.fontFamily, fontSize: 16, fontWeight: FontWeight.w500),
              tabs: const [
                Tab(text: 'Details', height: 52),
                Tab(text: 'Lifecycle', height: 52),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _DetailsTab(asset: asset),
                AssetHistoryTimeline(assetId: asset.id),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailsTab extends ConsumerWidget {
  final AssetModel asset;
  const _DetailsTab({required this.asset});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    return ListView(
      // outside the tab-bar shell (opened from History, Maintenance, Reports…): clear only the phone's own inset
      padding: EdgeInsets.fromLTRB(16, 16, 16, 24 + MediaQuery.of(context).padding.bottom),
      children: [
        // Summary: property no., name, status, location - then the everyday actions as worded buttons
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(asset.propertyNumber,
                    style: TextStyle(
                      color: c.textTertiary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'monospace',
                    )),
                const SizedBox(height: 4),
                Text(asset.description,
                    style: TextStyle(color: c.heading, fontSize: 21, height: 1.25, fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    StatusBadge.condition(asset.condition),
                    StatusBadge.lifecycle(asset.lifecycleStatus),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(Icons.apartment_rounded, size: 18, color: c.textTertiary),
                    const SizedBox(width: 8),
                    Expanded(child: Text(asset.office.officeName, style: TextStyle(fontSize: 15, color: c.textSecondary))),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.qr_code_2_rounded, size: 20),
                        label: const Text('QR Code'),
                        style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 6)),
                        onPressed: () => showAssetQrSheet(context, asset),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.photo_camera_outlined, size: 20),
                        label: const Text('Photos'),
                        style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 6)),
                        onPressed: () => showEvidenceSheet(
                          context,
                          path: '/assets/${asset.id}/evidence',
                          title: 'Asset Evidence',
                          subtitle: '${asset.propertyNumber}: ${asset.description}',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.icon(
                        icon: const Icon(Icons.edit_rounded, size: 20),
                        label: const Text('Edit'),
                        style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 6)),
                        onPressed: () async {
                          final result = await context.push<bool>('/assets/${asset.id}/edit', extra: asset);
                          if (result == true) ref.invalidate(assetDetailProvider(asset.id));
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.swap_horiz_rounded, size: 20),
                  label: const Text('Transfer to another office'),
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  onPressed: () async {
                    final moved = await context.push<bool>('/transfers/new', extra: asset);
                    if (moved == true) {
                      ref.invalidate(assetDetailProvider(asset.id));
                      ref.invalidate(returnPapersProvider(asset.id));
                    }
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _AiRecommendationCard(assetId: asset.id),
        const SizedBox(height: 12),
        _card(context, 'Asset Details', [
          _row(context, 'PAR Number', asset.parNumber ?? 'N/A'),
          if (asset.serialNumber != null && asset.serialNumber!.isNotEmpty)
            _row(context, 'Serial Number', asset.serialNumber!),
          _row(context, 'Category', asset.category.categoryName),
          _row(context, 'Article', asset.article?.articleName ?? 'N/A'),
          _row(context, 'Location', asset.office.officeName),
          if (asset.accountablePerson != null) _row(context, 'Accountable Person', asset.accountablePerson!.fullName),
          if (asset.currentUser != null) _row(context, 'Current User', asset.currentUser!.fullName),
          _row(context, 'Qty (Property Card)', asset.quantity.toString()),
          if (asset.physicalCount != null)
            _row(context, 'Qty (Physical Count)', asset.physicalCount.toString()),
          ..._shortageOverageRows(context, asset),
        ]),
        ReturnPapersCard(assetId: asset.id),
        const SizedBox(height: 12),
        _card(context, 'Financial', [
          _row(context, 'Unit Value', fmtMoney(asset.unitValue)),
          _row(context, 'Acquisition Date', asset.acquisitionDate),
          _row(context, 'Expected Life', expectedLifeText(asset)),
        ]),
        if (asset.specifications != null && asset.specifications!.isNotEmpty) ...[
          const SizedBox(height: 12),
          SectionCard(
            title: 'Technical Specifications',
            child: Text(asset.specifications!, style: TextStyle(color: c.textSecondary, fontSize: 15, height: 1.5)),
          ),
        ],
        if (asset.remarks != null && asset.remarks!.isNotEmpty) ...[
          const SizedBox(height: 12),
          SectionCard(
            title: 'Remarks',
            child: Text(asset.remarks!, style: TextStyle(color: c.textSecondary, fontSize: 15, height: 1.5)),
          ),
        ],
        const SizedBox(height: 12),
        _card(context, 'Record Info', [
          _row(context, 'Created', _fmt(asset.createdAt)),
          _row(context, 'Last Updated', _fmt(asset.updatedAt)),
        ]),
      ],
    );
  }

  // A label/value list in a section card, each row divided by a hairline - easy to scan
  Widget _card(BuildContext context, String title, List<Widget> rows) => SectionCard(
        title: title,
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) Divider(height: 1, indent: 16, color: context.colors.border),
              rows[i],
            ],
          ],
        ),
      );

  Widget _row(BuildContext context, String label, String value, {Color? valueColor}) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 5,
              child: Text(label, style: TextStyle(color: context.colors.textTertiary, fontSize: 15)),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 6,
              child: Text(value,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      color: valueColor ?? context.colors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );

  // Manually entered, independent of Qty/Physical Count (both always 1). Negative =
  // shortage (red), positive = overage (green) - same convention as the web app.
  List<Widget> _shortageOverageRows(BuildContext context, AssetModel asset) {
    final diff = asset.shortageOverageQty;
    final value = asset.shortageOverageValue;
    final color = diff < 0 ? AppTheme.statusDisposed : diff > 0 ? context.brandAccent : context.colors.textPrimary;
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
      final dt = DateTime.parse(raw).toLocal();
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    } catch (_) {
      return raw;
    }
  }
}

/// One asset's timeline: its history events, maintenance and disposal records, newest first.
/// The asset page's History tab, and the sheet opened from a scanned QR ([showAssetHistorySheet]).
class AssetHistoryTimeline extends ConsumerWidget {
  final int assetId;
  /// Given when the timeline sits in a draggable sheet, so scrolling it also drags the sheet.
  final ScrollController? controller;
  const AssetHistoryTimeline({super.key, required this.assetId, this.controller});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(assetHistoryProvider(assetId));
    final maintenanceAsync = ref.watch(maintenanceByAssetProvider(assetId));
    final disposalAsync = ref.watch(disposalByAssetProvider(assetId));

    if (historyAsync.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (historyAsync.hasError) {
      return Center(
        child: Text(historyAsync.error.toString(), style: TextStyle(color: context.colors.textTertiary)),
      );
    }

    final entries = <_LifecycleEntry>[
      ...(historyAsync.valueOrNull ?? []).map(_LifecycleEntry.fromHistory),
      ...(maintenanceAsync.valueOrNull ?? []).map(_LifecycleEntry.fromMaintenance),
      ...(disposalAsync.valueOrNull ?? []).map(_LifecycleEntry.fromDisposal),
    ]..sort((a, b) => b.sortDate.compareTo(a.sortDate));

    return entries.isEmpty
        ? Center(child: Text('No lifecycle events recorded.', style: TextStyle(color: context.colors.textTertiary)))
        : ListView.builder(
            controller: controller,
            padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(context).padding.bottom),
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
  // eventDate regardless of true recency - sortDate uses updatedAt/createdAt
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
    final date = DateTime.tryParse(h.eventDate)?.toLocal() ?? DateTime.now();
    return _LifecycleEntry(
      id: 'h-${h.id}',
      date: date,
      sortDate: date,
      title: _titleCase(h.eventType),
      color: _historyColor(h.eventType),
      icon: _historyIcon(h.eventType),
      meta: 'by ${h.performedBy.fullName}',
      note: h.notes,
      fromOffice: h.fromOffice?.officeName,
      toOffice: h.toOffice?.officeName,
    );
  }

  factory _LifecycleEntry.fromMaintenance(MaintenanceModel m) {
    final date = DateTime.tryParse(m.maintenanceDate)?.toLocal() ?? DateTime.now();
    final sortDate = DateTime.tryParse(m.updatedAt ?? m.createdAt)?.toLocal() ?? date;
    return _LifecycleEntry(
      id: 'm-${m.id}',
      date: date,
      sortDate: sortDate,
      title: 'Maintenance – ${_titleCase(m.maintenanceType)}',
      color: AppTheme.statusMaintenance,
      icon: Icons.build_outlined,
      meta: 'by ${m.recordedBy.fullName}',
      subtitle: m.cost != null ? '₱${m.cost!.toStringAsFixed(2)}' : null,
      note: m.findings,
      badge: StatusBadge.maintenanceStatus(m.status, dense: true),
    );
  }

  factory _LifecycleEntry.fromDisposal(DisposalModel d) {
    final date = DateTime.tryParse(d.inspectionDate)?.toLocal() ?? DateTime.now();
    final sortDate = DateTime.tryParse(d.updatedAt ?? d.createdAt)?.toLocal() ?? date;
    return _LifecycleEntry(
      id: 'd-${d.id}',
      date: date,
      sortDate: sortDate,
      title: 'Disposal – ${_titleCase(d.recommendedMethod)}',
      color: AppTheme.statusDisposed,
      icon: Icons.delete_outline_rounded,
      meta: 'by ${d.recordedBy.fullName}',
      subtitle: 'Inspected ${_fmtStatic(d.inspectionDate)}',
      note: d.reason,
      badge: StatusBadge.disposalStatus(d.disposalStatus, dense: true),
    );
  }

  static Color _historyColor(String eventType) => switch (eventType) {
        'REGISTERED' => AppTheme.statusRegistered,
        'ASSIGNED' => AppTheme.statusAssigned,
        'TRANSFERRED' => AppTheme.statusTransferred,
        'MAINTENANCE' => AppTheme.statusMaintenance,
        'DISPOSAL' => AppTheme.statusDisposed,
        'ARCHIVED' => AppTheme.statusArchived,
        _ => AppTheme.statusArchived,
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
      final dt = DateTime.parse(raw).toLocal();
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
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: entry.color.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                  border: Border.all(color: entry.color.withValues(alpha: 0.5)),
                ),
                child: Icon(entry.icon, size: 18, color: entry.color),
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
                            style: TextStyle(color: context.colors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
                      ),
                      if (entry.badge != null) entry.badge!,
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(_fmt(entry.date),
                      style: TextStyle(color: context.colors.textTertiary, fontSize: 14)),
                  if (entry.fromOffice != null || entry.toOffice != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (entry.fromOffice != null)
                          Flexible(child: Text(entry.fromOffice!,
                              style: TextStyle(color: context.colors.textTertiary, fontSize: 14))),
                        if (entry.fromOffice != null && entry.toOffice != null)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            child: Icon(Icons.arrow_forward_rounded, size: 16, color: context.colors.textSecondary),
                          ),
                        if (entry.toOffice != null)
                          Flexible(child: Text(entry.toOffice!,
                              style: TextStyle(color: context.colors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600))),
                      ],
                    ),
                  ],
                  if (entry.subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(entry.subtitle!, style: TextStyle(color: context.colors.textSecondary, fontSize: 14)),
                  ],
                  if (entry.note != null && entry.note!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(entry.note!, style: TextStyle(color: context.colors.textSecondary, fontSize: 14, height: 1.4)),
                  ],
                  if (entry.meta != null) ...[
                    const SizedBox(height: 2),
                    Text(entry.meta!, style: TextStyle(color: context.colors.textTertiary, fontSize: 13)),
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
        'MONITOR' => AppTheme.info,
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
      final dt = DateTime.parse(raw).toLocal();
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    } catch (_) {
      return raw;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Any role can generate - web's asset drawer doesn't gate it either.
    final recAsync = ref.watch(aiRecommendationProvider(widget.assetId));

    ref.listen<AsyncValue<AiRecommendationModel?>>(
      aiRecommendationProvider(widget.assetId),
      (previous, next) {
        if (!_generating && !_autoGenerateAttempted && next.hasValue && next.value == null) {
          _autoGenerateAttempted = true;
          _generate(silent: true);
        }
      },
    );

    return SectionCard(
      title: 'AI Recommendation',
      trailing: _generating
          ? const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            )
          : TextButton(onPressed: _generate, child: const Text('Generate')),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Text(
                key: const ValueKey('error'),
                e.toString(),
                style: TextStyle(color: context.colors.textSecondary, fontSize: 14),
              ),
              data: (rec) {
                if (rec == null) {
                  if (_generating) {
                    return Row(
                      key: const ValueKey('generating'),
                      children: [
                        const SizedBox(
                          width: 14, height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 10),
                        Text('Generating recommendation…',
                            style: TextStyle(color: context.colors.textSecondary, fontSize: 15)),
                      ],
                    );
                  }
                  return Text(
                    key: const ValueKey('empty'),
                    'No recommendation yet. Tap Generate to get one.',
                    style: TextStyle(color: context.colors.textSecondary, fontSize: 15),
                  );
                }
                final color = _color(rec.recommendation);
                return Column(
                  key: ValueKey('data-${rec.recommendation}-${rec.generatedAt}'),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    StatusBadge(label: _label(rec.recommendation), color: color),
                    const SizedBox(height: 10),
                    Text(rec.rationale, style: TextStyle(color: context.colors.textSecondary, fontSize: 15, height: 1.5)),
                    const SizedBox(height: 10),
                    Text('Generated ${_fmtDate(rec.generatedAt)} · advisory only, not a final decision',
                        style: TextStyle(color: context.colors.textTertiary, fontSize: 13)),
                  ],
                );
              },
              ),
            ),
          ],
        ),
    );
  }
}

/// "UNDER_MAINTENANCE" → "Under Maintenance"
String _titleCase(String raw) => raw
    .split('_')
    .where((w) => w.isNotEmpty)
    .map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase())
    .join(' ');

// The category's expected useful life, counted from the acquisition date.
String expectedLifeText(AssetModel asset) {
  final years = asset.category.usefulLifeYears;
  if (years == null) return 'Not set for this category';
  final label = '$years year${years == 1 ? '' : 's'}';
  final acquired = DateTime.tryParse(asset.acquisitionDate);
  if (acquired == null) return label;
  final end = DateTime(acquired.year + years, acquired.month, acquired.day);
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final when = '${months[end.month - 1]} ${end.year}';
  return end.isBefore(DateTime.now()) ? '$label · ended $when' : '$label · ends $when';
}
