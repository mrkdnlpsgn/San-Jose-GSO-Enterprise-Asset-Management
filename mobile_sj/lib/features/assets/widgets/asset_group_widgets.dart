import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/status_badge.dart';
import '../../../shared/provider/paginated_list_notifier.dart';
import '../../asset_history/data/asset_history_service.dart';
import '../../disposal/data/disposal_service.dart';
import '../../maintenance/data/maintenance_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/provider/auth_provider.dart';
import '../data/ai_recommendation_service.dart';
import '../data/asset_service.dart';
import '../model/ai_recommendation_model.dart';
import '../model/asset_model.dart';

// Widgets for a group of same-model devices (assets added together that share a groupId).
// Every device is still its own complete asset; these are the roll-up views:
//   GroupDevicesTable — every device in a table (same columns as the web asset table) + search
//   showAssetGroupSheet — Details (overview + "View Devices"), a Lifecycle tab that can be filtered
//                         by device and by lifecycle event, and an AI Insight tab (per device)

String _money(double v) => '₱${v.toStringAsFixed(2)}';

// One device's lifecycle source failing shouldn't blank the whole feed.
Future<List<T>> _orEmpty<T>(Future<List<T>> Function() load) async {
  try {
    return await load();
  } catch (_) {
    return <T>[];
  }
}

/// The devices as a table with a search box over property/PAR number, serial number and the
/// people involved.
class GroupDevicesTable extends StatefulWidget {
  final List<AssetModel> members;
  final void Function(AssetModel) onOpen;

  const GroupDevicesTable({super.key, required this.members, required this.onOpen});

  @override
  State<GroupDevicesTable> createState() => _GroupDevicesTableState();
}

class _GroupDevicesTableState extends State<GroupDevicesTable> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    bool matches(AssetModel a) => [
          a.propertyNumber,
          a.parNumber,
          a.serialNumber,
          a.accountablePerson?.fullName,
          a.currentUser?.fullName,
        ].any((v) => v != null && v.toLowerCase().contains(q));
    final members = widget.members;
    final shown = q.isEmpty ? members : members.where(matches).toList();
    final small = TextStyle(color: context.colors.textTertiary, fontSize: 11);
    const mono = TextStyle(fontFamily: 'monospace', fontSize: 12);

    DataColumn col(String label, {bool numeric = false}) => DataColumn(
          label: Text(label, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
          numeric: numeric,
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          onChanged: (v) => setState(() => _query = v),
          decoration: InputDecoration(
            isDense: true,
            prefixIcon: const Icon(Icons.search_rounded, size: 20),
            hintText: 'Search property no., PAR no., serial no. or person…',
            helperText: q.isEmpty ? '${members.length} devices' : '${shown.length} of ${members.length} devices',
          ),
        ),
        const SizedBox(height: 8),
        if (shown.isEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Center(child: Text('No devices match "$_query".', style: small)),
          )
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              showCheckboxColumn: false,
              columnSpacing: 20,
              dataRowMinHeight: 56,
              dataRowMaxHeight: 96,
              columns: [
                col('Property No.'),
                col('PAR No.'),
                col('Description'),
                col('Category'),
                col('Qty (Property Card)', numeric: true),
                col('Qty (Physical Count)', numeric: true),
                col('Shortage/Overage Qty', numeric: true),
                col('Shortage/Overage Value', numeric: true),
                col('Location'),
                col('Unit Value', numeric: true),
                col('Date'),
                col('Remarks'),
              ],
              rows: [
                for (final m in shown)
                  DataRow(
                    onSelectChanged: (_) => widget.onOpen(m),
                    cells: [
                      DataCell(Text(m.propertyNumber, style: mono)),
                      DataCell(Text(m.parNumber ?? '—', style: mono)),
                      DataCell(Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 200),
                            child: Text(m.description,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
                          ),
                          if ((m.serialNumber ?? '').isNotEmpty) Text('S/N ${m.serialNumber}', style: small),
                          if (m.accountablePerson != null)
                            Text('Accountable: ${m.accountablePerson!.fullName}', style: small),
                          if (m.currentUser != null) Text('Using: ${m.currentUser!.fullName}', style: small),
                        ],
                      )),
                      DataCell(Text(m.category.categoryName)),
                      DataCell(Text('${m.quantity}')),
                      DataCell(Text(m.physicalCount?.toString() ?? '—')),
                      DataCell(Text(m.physicalCount == null ? '—' : '${m.physicalCount! - m.quantity}')),
                      DataCell(Text(m.physicalCount == null
                          ? '—'
                          : _money((m.physicalCount! - m.quantity) * m.unitValue))),
                      DataCell(Text(m.office.officeName)),
                      DataCell(Text(_money(m.unitValue))),
                      DataCell(Text(m.acquisitionDate)),
                      DataCell(Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          StatusBadge.condition(m.condition),
                          if ((m.remarks ?? '').isNotEmpty)
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 160),
                              child: Text(m.remarks!, maxLines: 2, overflow: TextOverflow.ellipsis, style: small),
                            ),
                        ],
                      )),
                    ],
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Full-screen page with every device of a group (the "View Devices" button).
class GroupDevicesPage extends StatelessWidget {
  final String title;
  final List<AssetModel> members;
  final void Function(AssetModel) onOpen;

  const GroupDevicesPage({super.key, required this.title, required this.members, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title, overflow: TextOverflow.ellipsis)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: GroupDevicesTable(members: members, onOpen: onOpen),
      ),
    );
  }
}

/// Bottom sheet for a group: Details tab (overview + View Devices) and Lifecycle tab
/// (every device's events, filterable by device and by lifecycle event).
Future<void> showAssetGroupSheet(
  BuildContext context, {
  required String groupId,
  required String description,
  required void Function(AssetModel) onOpenDevice,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.92,
      child: _GroupSheet(groupId: groupId, description: description, onOpenDevice: onOpenDevice),
    ),
  );
}

// One row of the merged lifecycle feed.
class _Event {
  final int device; // index into the group's members
  final String kind; // REGISTERED | TRANSFERRED | MAINTENANCE | DISPOSAL | …
  final String type; // history | maintenance | disposal
  final String title;
  final String? status;
  final String date;
  final String? note;
  final String? meta;

  const _Event({
    required this.device,
    required this.kind,
    required this.type,
    required this.title,
    required this.date,
    this.status,
    this.note,
    this.meta,
  });
}

class _GroupSheet extends StatefulWidget {
  final String groupId;
  final String description;
  final void Function(AssetModel) onOpenDevice;

  const _GroupSheet({required this.groupId, required this.description, required this.onOpenDevice});

  @override
  State<_GroupSheet> createState() => _GroupSheetState();
}

class _GroupSheetState extends State<_GroupSheet> {
  List<AssetModel>? _members;
  List<_Event>? _events;
  Object? _error;
  int? _deviceFilter;
  String? _typeFilter;
  // AI Insight tab: latest recommendation per device id (missing key = still loading, null = none yet)
  final Map<int, AiRecommendationModel?> _recs = {};
  final Set<int> _generating = {};
  int? _aiDevice;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final members = await AssetService().getGroup(widget.groupId);
      if (!mounted) return;
      setState(() => _members = members);

      final ai = AiRecommendationService();
      // Best-effort: a device whose recommendation can't be read just shows as "none yet".
      for (final m in members) {
        ai.getLatest(m.id).then((r) {
          if (mounted) setState(() => _recs[m.id] = r);
        }).catchError((_) {
          if (mounted) setState(() => _recs[m.id] = null);
        });
      }

      final history = AssetHistoryService();
      final maintenance = MaintenanceService();
      final disposal = DisposalService();
      final events = <_Event>[];
      // Per-device calls (the API has no group-wide lifecycle endpoint), run in parallel.
      await Future.wait([
        for (var i = 0; i < members.length; i++)
          (() async {
            final id = members[i].id;
            final h = await _orEmpty(() => history.getByAsset(id));
            final m = await _orEmpty(() => maintenance.getByAsset(id));
            final d = await _orEmpty(() => disposal.getByAsset(id));
            for (final e in h) {
              events.add(_Event(
                device: i,
                kind: e.eventType.toUpperCase(),
                type: 'history',
                title: e.eventType,
                date: e.eventDate,
                note: e.notes,
                meta: 'By: ${e.performedBy.fullName}',
              ));
            }
            for (final e in m) {
              events.add(_Event(
                device: i,
                kind: 'MAINTENANCE',
                type: 'maintenance',
                title: 'Maintenance – ${e.maintenanceType}',
                status: e.status,
                date: e.maintenanceDate,
                note: e.findings,
                meta: e.cost != null ? _money(e.cost!) : null,
              ));
            }
            for (final e in d) {
              events.add(_Event(
                device: i,
                kind: 'DISPOSAL',
                type: 'disposal',
                title: 'Disposal – ${e.recommendedMethod}',
                status: e.disposalStatus,
                date: e.inspectionDate,
                note: e.reason,
              ));
            }
          })(),
      ]);
      events.sort((a, b) => b.date.compareTo(a.date));
      if (mounted) setState(() => _events = events);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  String _deviceName(int i) => 'Device ${i + 1} · ${_members![i].propertyNumber}';

  bool get _isAdmin => ProviderScope.containerOf(context, listen: false).read(authProvider).value?.isAdmin ?? false;

  Future<void> _generate(int assetId) async {
    setState(() => _generating.add(assetId));
    try {
      final rec = await AiRecommendationService().generate(assetId);
      if (mounted) setState(() => _recs[assetId] = rec);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: Colors.red.shade800));
      }
    } finally {
      if (mounted) setState(() => _generating.remove(assetId));
    }
  }

  // One after another — each call asks the AI model, so they aren't fired all at once.
  Future<void> _generateMissing(List<AssetModel> members) async {
    for (final m in members) {
      if (_recs[m.id] == null && !_generating.contains(m.id)) await _generate(m.id);
    }
  }

  Color _recColor(String rec) => switch (rec) {
        'MAINTAIN' => AppTheme.brand,
        'REPAIR' => AppTheme.statusMaintenance,
        'MONITOR' => AppTheme.statusAssigned,
        'REVIEW_FOR_DISPOSAL' => AppTheme.statusDisposed,
        'BUDGET_PRIORITY' => Colors.deepOrange,
        _ => Colors.grey,
      };

  @override
  Widget build(BuildContext context) {
    final members = _members;
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(members == null ? 'Group' : '${members.length} devices · same model',
                      style: const TextStyle(color: AppTheme.brand, fontSize: 12, fontWeight: FontWeight.w600)),
                  Text(widget.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: context.colors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
          const TabBar(tabs: [Tab(text: 'Details'), Tab(text: 'Lifecycle'), Tab(text: 'AI Insight')]),
          Expanded(
            child: _error != null
                ? Center(child: Text('Couldn\'t load this group.', style: TextStyle(color: context.colors.textTertiary)))
                : members == null
                    ? const Center(child: CircularProgressIndicator(color: AppTheme.brand))
                    : TabBarView(children: [_details(context, members), _lifecycle(context, members), _aiInsight(context, members)]),
          ),
        ],
      ),
    );
  }

  Widget _details(BuildContext context, List<AssetModel> members) {
    Map<String, int> count(String Function(AssetModel) pick) {
      final out = <String, int>{};
      for (final m in members) {
        out[pick(m)] = (out[pick(m)] ?? 0) + 1;
      }
      return out;
    }

    final total = members.fold<double>(0, (n, m) => n + m.unitValue * m.quantity);
    Widget row(String label, String value) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 110, child: Text(label, style: TextStyle(color: context.colors.textSecondary, fontSize: 13))),
              Expanded(child: Text(value, style: TextStyle(color: context.colors.textPrimary, fontSize: 13))),
            ],
          ),
        );

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        row('Category', members.first.category.categoryName),
        row('Devices', '${members.length}'),
        row('Total Value', _money(total)),
        row('Condition', count((m) => m.condition).entries.map((e) => '${e.value} ${e.key}').join(' · ')),
        row('Lifecycle',
            count((m) => m.lifecycleStatus).entries.map((e) => '${e.value} ${e.key.replaceAll('_', ' ')}').join(' · ')),
        const SizedBox(height: 8),
        SizedBox(
          height: 48,
          child: ElevatedButton.icon(
            icon: const Icon(Icons.table_rows_outlined),
            label: Text('View Devices (${members.length})'),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => GroupDevicesPage(
                title: widget.description,
                members: members,
                onOpen: (a) {
                  // close the devices page and this sheet, then open the device
                  final nav = Navigator.of(context);
                  nav.pop();
                  nav.pop();
                  widget.onOpenDevice(a);
                },
              ),
            )),
          ),
        ),
        const SizedBox(height: 8),
        Text('Every device with its own Property No., PAR No., people, price and condition — searchable.',
            textAlign: TextAlign.center, style: TextStyle(color: context.colors.textTertiary, fontSize: 12)),
      ],
    );
  }

  Widget _aiInsight(BuildContext context, List<AssetModel> members) {
    final isAdmin = _isAdmin;
    final anyGenerating = _generating.isNotEmpty;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        DropdownButtonFormField<int?>(
          initialValue: _aiDevice,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Device'),
          dropdownColor: context.colors.surface,
          items: [
            const DropdownMenuItem<int?>(value: null, child: Text('All devices')),
            for (var i = 0; i < members.length; i++)
              DropdownMenuItem<int?>(value: i, child: Text(_deviceName(i), overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (v) => setState(() => _aiDevice = v),
        ),
        if (isAdmin) ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: anyGenerating ? null : () => _generateMissing(members),
            icon: const Icon(Icons.auto_awesome_rounded, size: 18),
            label: const Text('Generate missing'),
          ),
        ],
        const SizedBox(height: 12),
        for (var i = 0; i < members.length; i++)
          if (_aiDevice == null || _aiDevice == i)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(_deviceName(i),
                              style: const TextStyle(color: AppTheme.brand, fontSize: 11.5, fontWeight: FontWeight.w600)),
                        ),
                        if (isAdmin)
                          _generating.contains(members[i].id)
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.brand))
                              : TextButton(
                                  onPressed: () => _generate(members[i].id),
                                  child: Text(_recs[members[i].id] == null ? 'Generate' : 'Regenerate'),
                                ),
                      ],
                    ),
                    if (!_recs.containsKey(members[i].id))
                      Text('Loading…', style: TextStyle(color: context.colors.textTertiary, fontSize: 12))
                    else if (_recs[members[i].id] == null)
                      Text(isAdmin ? 'No recommendation yet. Tap Generate.' : 'No recommendation generated yet.',
                          style: TextStyle(color: context.colors.textSecondary, fontSize: 13))
                    else ...[
                      Builder(builder: (_) {
                        final rec = _recs[members[i].id]!;
                        final color = _recColor(rec.recommendation);
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: color.withValues(alpha: 0.4)),
                              ),
                              child: Text(rec.recommendation.replaceAll('_', ' '),
                                  style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
                            ),
                            const SizedBox(height: 8),
                            Text(rec.rationale,
                                style: TextStyle(color: context.colors.textSecondary, fontSize: 13, height: 1.4)),
                            const SizedBox(height: 6),
                            Text(
                                'Age ${rec.assetAgeYears} yrs · repairs ${rec.repairFrequency} · cost ${_money(rec.totalRepairCost)} · '
                                'score ${rec.conditionScore} · ${rec.generatedAt.length >= 10 ? rec.generatedAt.substring(0, 10) : rec.generatedAt}',
                                style: TextStyle(color: context.colors.textTertiary, fontSize: 11)),
                          ],
                        );
                      }),
                    ],
                  ],
                ),
              ),
            ),
        Text('Advisory only — not a final decision.',
            textAlign: TextAlign.center, style: TextStyle(color: context.colors.textTertiary, fontSize: 11.5)),
      ],
    );
  }

  Widget _lifecycle(BuildContext context, List<AssetModel> members) {
    final events = _events;
    if (events == null) return const Center(child: CircularProgressIndicator(color: AppTheme.brand));

    final kinds = events.map((e) => e.kind).toSet().toList()..sort();
    final visible = events
        .where((e) => (_deviceFilter == null || e.device == _deviceFilter) && (_typeFilter == null || e.kind == _typeFilter))
        .toList();
    String pretty(String k) => k.isEmpty ? k : '${k[0]}${k.substring(1).toLowerCase().replaceAll('_', ' ')}';

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        DropdownButtonFormField<int?>(
          initialValue: _deviceFilter,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Device'),
          dropdownColor: context.colors.surface,
          items: [
            const DropdownMenuItem<int?>(value: null, child: Text('All devices')),
            for (var i = 0; i < members.length; i++)
              DropdownMenuItem<int?>(value: i, child: Text(_deviceName(i), overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (v) => setState(() => _deviceFilter = v),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String?>(
          initialValue: _typeFilter,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Lifecycle event'),
          dropdownColor: context.colors.surface,
          items: [
            const DropdownMenuItem<String?>(value: null, child: Text('All events')),
            for (final k in kinds) DropdownMenuItem<String?>(value: k, child: Text(pretty(k))),
          ],
          onChanged: (v) => setState(() => _typeFilter = v),
        ),
        const SizedBox(height: 10),
        Text(
          '${visible.length} event${visible.length == 1 ? '' : 's'}'
          '${_deviceFilter != null || _typeFilter != null ? ' of ${events.length}' : ''}',
          style: TextStyle(color: context.colors.textTertiary, fontSize: 12),
        ),
        const SizedBox(height: 8),
        if (visible.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Center(child: Text('No lifecycle events match.', style: TextStyle(color: context.colors.textTertiary))),
          )
        else
          for (final e in visible)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_deviceName(e.device),
                        style: const TextStyle(color: AppTheme.brand, fontSize: 11.5, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: Text(e.title,
                              style: TextStyle(
                                  color: context.colors.textPrimary, fontSize: 13.5, fontWeight: FontWeight.w600)),
                        ),
                        if (e.status != null)
                          Text(e.status!, style: TextStyle(color: context.colors.textSecondary, fontSize: 11.5)),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(e.date.length >= 10 ? e.date.substring(0, 10) : e.date,
                        style: TextStyle(color: context.colors.textTertiary, fontSize: 12)),
                    if (e.meta != null)
                      Text(e.meta!, style: TextStyle(color: context.colors.textSecondary, fontSize: 12)),
                    if ((e.note ?? '').isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(e.note!,
                            style: TextStyle(
                                color: context.colors.textSecondary, fontSize: 12, fontStyle: FontStyle.italic)),
                      ),
                  ],
                ),
              ),
            ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Grouping for record lists (Maintenance, Disposal, Reports): rows whose device belongs to
// the same group (same model) collapse into one expandable card; every row inside is still
// a complete record.
// ─────────────────────────────────────────────────────────────────────────────

class RecordEntry<T> {
  final List<T> members;
  const RecordEntry(this.members);
  bool get isGroup => members.length > 1;
}

/// Groups `items` by group id (first occurrence keeps its position). A group with a single
/// row is just a normal row.
List<RecordEntry<T>> groupRecords<T>(List<T> items, String? Function(T) groupIdOf) {
  final entries = <RecordEntry<T>>[];
  final byGroup = <String, List<T>>{};
  for (final item in items) {
    final g = groupIdOf(item);
    if (g == null) {
      entries.add(RecordEntry<T>([item]));
    } else if (byGroup.containsKey(g)) {
      byGroup[g]!.add(item);
    } else {
      final members = <T>[item];
      byGroup[g] = members;
      entries.add(RecordEntry<T>(members));
    }
  }
  return entries;
}

PaginatedListState<RecordEntry<T>> groupRecordsState<T>(
    PaginatedListState<T> s, String? Function(T) groupIdOf) {
  return PaginatedListState<RecordEntry<T>>(
    items: groupRecords(s.items, groupIdOf),
    isLoading: s.isLoading,
    isLoadingMore: s.isLoadingMore,
    hasMore: s.hasMore,
    error: s.error,
    loadMoreError: s.loadMoreError,
  );
}

/// Multi-line cell text for the device a record belongs to — includes the serial number and
/// people so a search hit is explainable.
String assetCellText(AssetModel a) => [
      a.propertyAndPar,
      a.description,
      if ((a.serialNumber ?? '').isNotEmpty) 'S/N ${a.serialNumber}',
      if (a.accountablePerson != null) 'Accountable: ${a.accountablePerson!.fullName}',
      if (a.currentUser != null) 'Using: ${a.currentUser!.fullName}',
    ].join('\n');

/// An expandable card for a group of records. Expanding shows the records as a table (same
/// columns as the screen's rows) with a search box over property/PAR number, serial number and
/// the people involved; the ⓘ button opens the group sheet (Details + filterable Lifecycle).
class RecordGroupCard<T> extends StatefulWidget {
  final List<T> members;
  final AssetModel? Function(T) assetOf;
  final String noun; // 'records' | 'rows'
  final List<String> columns;
  final List<String> Function(T) values;
  final void Function(T)? onOpenRecord;
  final void Function(AssetModel) onOpenDevice;
  final Widget? summary;

  const RecordGroupCard({
    super.key,
    required this.members,
    required this.assetOf,
    required this.noun,
    required this.columns,
    required this.values,
    required this.onOpenDevice,
    this.onOpenRecord,
    this.summary,
  });

  @override
  State<RecordGroupCard<T>> createState() => _RecordGroupCardState<T>();
}

class _RecordGroupCardState<T> extends State<RecordGroupCard<T>> {
  bool _expanded = false;
  String _query = '';

  bool _matches(T r, String q) {
    final a = widget.assetOf(r);
    if (a == null) return false;
    return [a.propertyNumber, a.parNumber, a.serialNumber, a.accountablePerson?.fullName, a.currentUser?.fullName]
        .any((v) => v != null && v.toLowerCase().contains(q));
  }

  @override
  Widget build(BuildContext context) {
    final members = widget.members;
    final firstAsset = widget.assetOf(members.first);
    final groupId = firstAsset?.groupId;
    final devices = members.map((m) => widget.assetOf(m)?.id).toSet().length;
    final q = _query.trim().toLowerCase();
    final shown = q.isEmpty ? members : members.where((m) => _matches(m, q)).toList();
    final small = TextStyle(color: context.colors.textTertiary, fontSize: 11);

    return Card(
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(firstAsset?.description ?? 'Group',
                            style: TextStyle(
                                color: context.colors.textPrimary, fontSize: 15, fontWeight: FontWeight.w500),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 4),
                        Text('$devices device${devices == 1 ? '' : 's'} · same model',
                            style: TextStyle(color: context.colors.textTertiary, fontSize: 12)),
                        if (widget.summary != null) ...[const SizedBox(height: 4), widget.summary!],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppTheme.brand.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text('${members.length} ${widget.noun}',
                        style: const TextStyle(color: AppTheme.brand, fontSize: 11.5, fontWeight: FontWeight.w600)),
                  ),
                  if (groupId != null)
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Group details & lifecycle',
                      icon: const Icon(Icons.info_outline_rounded, color: AppTheme.brand),
                      onPressed: () => showAssetGroupSheet(
                        context,
                        groupId: groupId,
                        description: firstAsset?.description ?? 'Group',
                        onOpenDevice: widget.onOpenDevice,
                      ),
                    ),
                  Icon(_expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: AppTheme.brand),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    onChanged: (v) => setState(() => _query = v),
                    decoration: InputDecoration(
                      isDense: true,
                      prefixIcon: const Icon(Icons.search_rounded, size: 20),
                      hintText: 'Search property no., PAR no., serial no. or person…',
                      helperText: q.isEmpty
                          ? '${members.length} ${widget.noun}'
                          : '${shown.length} of ${members.length} ${widget.noun}',
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (shown.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Center(child: Text('No ${widget.noun} match "$_query".', style: small)),
                    )
                  else
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        showCheckboxColumn: false,
                        columnSpacing: 20,
                        dataRowMinHeight: 56,
                        dataRowMaxHeight: 110,
                        columns: [
                          for (final c in widget.columns)
                            DataColumn(label: Text(c, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600))),
                        ],
                        rows: [
                          for (final r in shown)
                            DataRow(
                              onSelectChanged: widget.onOpenRecord == null ? null : (_) => widget.onOpenRecord!(r),
                              cells: [
                                for (final v in widget.values(r))
                                  DataCell(ConstrainedBox(
                                    constraints: const BoxConstraints(maxWidth: 220),
                                    child: Text(v, maxLines: 5, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                                  )),
                              ],
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
