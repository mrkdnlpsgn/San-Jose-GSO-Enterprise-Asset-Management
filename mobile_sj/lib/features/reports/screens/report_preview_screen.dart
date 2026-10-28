import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_search_field.dart';
import '../../../shared/widgets/error_state.dart';
import '../data/report_definitions.dart';
import '../model/report_definition.dart';
import '../provider/reports_provider.dart';
import '../utils/report_format.dart';

// The same report panel as the web Reports page: the RPCPPE's report details, a search and
// tick-to-export list for the pick-and-export reports (RPCPPE, PAR, Property Card), a date range
// for the others, five rows a page, and Excel / Print-PDF exports in the same formats.

const _pageSize = 5;

const _presets = [('day', 'Today'), ('week', 'This Week'), ('month', 'This Month'), ('year', 'This Year')];

(String, String) _presetRange(String preset) {
  final now = DateTime.parse(todayKey());
  final to = dateKey(now);
  return switch (preset) {
    'day' => (to, to),
    'week' => (dateKey(now.subtract(const Duration(days: 6))), to),
    'month' => (dateKey(DateTime(now.year, now.month, 1)), to),
    'year' => (dateKey(DateTime(now.year, 1, 1)), to),
    _ => ('', ''),
  };
}

List<ReportRow> _applyDateFilter(List<ReportRow> rows, String? field, String from, String to) {
  if (field == null || (from.isEmpty && to.isEmpty)) return rows;
  return rows.where((r) {
    final v = r[field];
    if (v == null || v == '') return false;
    final d = manilaDateKey(v);
    if (from.isNotEmpty && d.compareTo(from) < 0) return false;
    if (to.isNotEmpty && d.compareTo(to) > 0) return false;
    return true;
  }).toList();
}

class ReportPreviewScreen extends ConsumerStatefulWidget {
  final String reportId;
  /// Replacement Forecast only: open on one "Replace in" group ('NOW' or a year), e.g. from Home.
  final String? replaceIn;
  const ReportPreviewScreen({super.key, required this.reportId, this.replaceIn});

  @override
  ConsumerState<ReportPreviewScreen> createState() => _ReportPreviewScreenState();
}

class _ReportPreviewScreenState extends ConsumerState<ReportPreviewScreen> {
  final _search = TextEditingController();
  String _from = '', _to = '', _query = '';
  late String _replaceIn = widget.replaceIn ?? ''; // '' = all
  int _page = 1;
  final Set<String> _picked = {};
  String? _expanded;
  bool _exporting = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _export(Future<void> Function() action) async {
    setState(() => _exporting = true);
    try {
      await action();
    } catch (e) {
      debugPrint('Report export failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Export failed. Please try again.'),
          backgroundColor: Colors.red.shade800,
        ));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  void _setDates(String from, String to) => setState(() {
        _from = from;
        _to = to;
        _page = 1;
      });

  @override
  Widget build(BuildContext context) {
    final report = ref.watch(reportDefinitionsProvider).firstWhere((r) => r.id == widget.reportId);
    final settings = ref.watch(rpcppeSettingsProvider);
    final dataAsync = ref.watch(reportDataProvider(widget.reportId));
    final c = context.colors;

    return Scaffold(
      appBar: AppBar(
        title: Text(report.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: () => ref.invalidate(reportDataProvider(widget.reportId)),
          ),
        ],
      ),
      body: dataAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorState(
          message: 'Failed to load report data.',
          onRetry: () => ref.invalidate(reportDataProvider(widget.reportId)),
        ),
        data: (data) {
          final pick = report.pick;
          final pickItems = pick != null ? pick.toItems(data, settings) : const <PickItem>[];
          final List<Object> display;
          if (pick != null) {
            final q = _query.trim().toLowerCase();
            display = q.isEmpty ? pickItems : pickItems.where((it) => pick.search(it, q)).toList();
          } else {
            var filtered = _applyDateFilter(data, report.dateField, _from, _to);
            if (report.id == 'replacement' && _replaceIn.isNotEmpty) {
              filtered = filtered.where((r) => r['replaceIn'] == _replaceIn).toList();
            }
            display = report.transform != null ? report.transform!(filtered) : filtered;
          }
          final dateFiltered = _from.isNotEmpty || _to.isNotEmpty || _replaceIn.isNotEmpty;
          // "Replace in" choices for the Replacement Forecast, in the order the backend sends them
          final replaceInOptions = report.id == 'replacement'
              ? data.map((r) => str(r['replaceIn'])).where((k) => k.isNotEmpty).toSet().toList()
              : const <String>[];
          final pickedItems = pickItems.where((it) => _picked.contains(it.key)).toList();
          final exportDisabled = pick != null && pickedItems.isEmpty;
          final count = pick != null && pickedItems.isNotEmpty ? ' (${pickedItems.length})' : '';
          final totalPages = (display.length / _pageSize).ceil().clamp(1, 1 << 30);
          final page = _page.clamp(1, totalPages);
          final paged = display.skip((page - 1) * _pageSize).take(_pageSize).toList();

          final noun = pick != null
              ? (display.length == 1 ? pick.noun.$1 : pick.noun.$2)
              : (display.length == 1 ? 'record' : 'records');
          String? ofTotal;
          if (pick != null && _query.trim().isNotEmpty && pickItems.length != display.length) ofTotal = '${pickItems.length}';
          if (pick == null && dateFiltered && !report.aggregated && data.length != display.length) ofTotal = '${data.length}';

          final children = <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text.rich(TextSpan(children: [
                TextSpan(text: '${display.length} $noun'),
                if (ofTotal != null) TextSpan(text: ' (of $ofTotal)', style: TextStyle(color: c.textTertiary)),
              ]), style: TextStyle(color: c.textSecondary, fontWeight: FontWeight.w700, fontSize: 15)),
            ),
            if (report.hasRpcppeSettings && data.isNotEmpty) _RpcppeDetails(settings: settings),
            if (pick != null && pickItems.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                child: AppSearchField(
                  controller: _search,
                  hintText: pick.placeholder,
                  onChanged: (v) => setState(() {
                    _query = v;
                    _page = 1;
                  }),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                child: pickedItems.isEmpty
                    ? Text(pick.hint, style: TextStyle(color: c.textSecondary, fontSize: 14))
                    : Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, children: [
                        Text('${pickedItems.length} selected',
                            style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.w600, fontSize: 14)),
                        Text('· ${pick.summary(pickedItems)}', style: TextStyle(color: c.textSecondary, fontSize: 14)),
                        TextButton(
                          onPressed: () => setState(_picked.clear),
                          style: TextButton.styleFrom(foregroundColor: Colors.red.shade400, padding: EdgeInsets.zero),
                          child: const Text('Clear selection'),
                        ),
                      ]),
              ),
              if (paged.isNotEmpty)
                CheckboxListTile(
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  tristate: true,
                  value: paged.every((it) => _picked.contains((it as PickItem).key))
                      ? true
                      : paged.any((it) => _picked.contains((it as PickItem).key))
                          ? null
                          : false,
                  onChanged: (_) => setState(() {
                    final all = paged.every((it) => _picked.contains((it as PickItem).key));
                    for (final it in paged) {
                      all ? _picked.remove((it as PickItem).key) : _picked.add((it as PickItem).key);
                    }
                  }),
                  title: Text('Select all ${pick.noun.$2} on this page', style: TextStyle(color: c.textSecondary, fontSize: 14)),
                ),
            ],
            if (replaceInOptions.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                child: Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Text('Replace in:', style: TextStyle(color: c.textSecondary, fontSize: 15, fontWeight: FontWeight.w600)),
                  for (final key in ['', ...replaceInOptions])
                    ChoiceChip(
                      label: Text(key.isEmpty ? 'All' : key == 'NOW' ? 'Now' : key),
                      selected: _replaceIn == key,
                      onSelected: (_) => setState(() {
                        _replaceIn = key;
                        _page = 1;
                      }),
                    ),
                ]),
              ),
            if (report.dateField != null && data.isNotEmpty) _DateFilter(from: _from, to: _to, onChange: _setDates),
          ];

          if (display.isEmpty) {
            final q = _query.trim();
            children.add(Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
              child: Column(children: [
                Icon(Icons.description_outlined, size: 40, color: c.textTertiary),
                const SizedBox(height: 8),
                Text(
                  pick != null
                      ? (pickItems.isNotEmpty ? 'No ${pick.noun.$2} match "$q".' : pick.none)
                      : data.isNotEmpty && dateFiltered
                          ? 'No records in the selected date range.'
                          : 'No data available for this report.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: c.textSecondary, fontSize: 15),
                ),
              ]),
            ));
          } else {
            for (final row in paged) {
              children.add(Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                child: pick != null
                    ? _PickCard(
                        config: pick,
                        item: row as PickItem,
                        checked: _picked.contains(row.key),
                        expanded: _expanded == row.key,
                        onToggle: () => setState(() => _picked.contains(row.key) ? _picked.remove(row.key) : _picked.add(row.key)),
                        onExpand: () => setState(() => _expanded = _expanded == row.key ? null : row.key),
                      )
                    : _RowCard(row: row as ReportRow, columns: report.headers),
              ));
            }
            if (display.length > _pageSize) {
              children.add(Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
                child: Row(children: [
                  Expanded(
                    child: Text(
                      '${(page - 1) * _pageSize + 1}–${(page * _pageSize).clamp(0, display.length)} of ${display.length}',
                      style: TextStyle(color: c.textTertiary, fontSize: 14),
                    ),
                  ),
                  OutlinedButton(onPressed: page > 1 ? () => setState(() => _page = page - 1) : null, child: const Text('Prev')),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Text('$page / $totalPages', style: TextStyle(color: c.textTertiary, fontSize: 14)),
                  ),
                  OutlinedButton(onPressed: page < totalPages ? () => setState(() => _page = page + 1) : null, child: const Text('Next')),
                ]),
              ));
            }
          }

          final exportRows = display.whereType<ReportRow>().toList();
          return Column(children: [
            Expanded(child: ListView(padding: const EdgeInsets.only(bottom: 8), children: children)),
            if (_exporting) const LinearProgressIndicator(color: AppTheme.brand),
            if (data.isNotEmpty)
              DecoratedBox(
                decoration: BoxDecoration(color: c.surface, border: Border(top: BorderSide(color: c.border))),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _exporting || exportDisabled
                              ? null
                              : () => _export(() => pick != null
                                  ? pick.exportExcel(pickedItems, settings)
                                  : exportReportExcel(report, exportRows)),
                          icon: const Icon(Icons.grid_on_rounded, size: 20),
                          label: Text('Excel$count'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _exporting || exportDisabled
                              ? null
                              : () => _export(() => pick != null
                                  ? pick.exportPdf(pickedItems, settings)
                                  : printTable(report, exportRows, _from, _to, settings)),
                          icon: const Icon(Icons.print_rounded, size: 20),
                          label: Text('Print / PDF$count'),
                        ),
                      ),
                    ]),
                  ),
                ),
              ),
          ]);
        },
      ),
    );
  }
}

/// A record as label / value pairs - the web table's columns, stacked to fit a phone.
class _RowCard extends StatelessWidget {
  final ReportRow row;
  final List<ReportColumn> columns;
  const _RowCard({required this.row, required this.columns});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        for (var i = 0; i < columns.length; i++) ...[
          if (i > 0) Divider(height: 1, indent: 14, color: c.border),
          _Pair(columns[i].label, columns[i].display(row), strong: i == 0),
        ],
      ]),
    );
  }
}

class _Pair extends StatelessWidget {
  final String label, value;
  final bool strong;
  const _Pair(this.label, this.value, {this.strong = false});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(flex: 4, child: Text(label, style: TextStyle(color: c.textTertiary, fontSize: 14))),
        const SizedBox(width: 10),
        Expanded(
          flex: 6,
          child: Text(value,
              textAlign: TextAlign.right,
              style: TextStyle(color: c.textPrimary, fontSize: 15, fontWeight: strong ? FontWeight.w700 : FontWeight.w500)),
        ),
      ]),
    );
  }
}

/// One pickable item: tick it to export it, expand it to see what's inside.
class _PickCard extends StatefulWidget {
  final PickConfig config;
  final PickItem item;
  final bool checked, expanded;
  final VoidCallback onToggle, onExpand;
  const _PickCard({
    required this.config,
    required this.item,
    required this.checked,
    required this.expanded,
    required this.onToggle,
    required this.onExpand,
  });

  @override
  State<_PickCard> createState() => _PickCardState();
}

class _PickCardState extends State<_PickCard> {
  // a type of PPE can hold hundreds of items; they are listed fifty at a time
  int _shown = 50;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final cfg = widget.config;
    final rows = widget.expanded ? cfg.expandedRows(widget.item) : const <ReportRow>[];
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: widget.checked ? AppTheme.brand : c.border, width: widget.checked ? 1.5 : 1),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          onTap: widget.onToggle,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Checkbox(
                value: widget.checked,
                onChanged: (_) => widget.onToggle(),
                semanticLabel: 'Select ${cfg.label(widget.item)}',
              ),
              Expanded(
                child: Column(children: [
                  for (var i = 0; i < cfg.columns.length; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Expanded(flex: 4, child: Text(cfg.columns[i].label, style: TextStyle(color: c.textTertiary, fontSize: 14))),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 6,
                          child: Text(cfg.columns[i].cell(widget.item),
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                  color: c.textPrimary, fontSize: 15, fontWeight: i == 0 ? FontWeight.w700 : FontWeight.w500)),
                        ),
                      ]),
                    ),
                ]),
              ),
              const SizedBox(width: 10),
            ]),
          ),
        ),
        Divider(height: 1, color: c.border),
        InkWell(
          onTap: widget.onExpand,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(children: [
              Expanded(
                child: Text('${widget.expanded ? 'Hide' : 'Show'} ${cfg.expandLabel}',
                    style: TextStyle(color: context.brandAccent, fontWeight: FontWeight.w600, fontSize: 14)),
              ),
              AnimatedRotation(
                turns: widget.expanded ? 0.25 : 0,
                duration: const Duration(milliseconds: 150),
                child: Icon(Icons.chevron_right_rounded, color: c.textTertiary),
              ),
            ]),
          ),
        ),
        if (widget.expanded)
          Container(
            color: c.subtle,
            padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (final r in rows.take(_shown))
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: _RowCard(row: r, columns: cfg.expandedHeaders),
                ),
              if (rows.length > _shown)
                TextButton(
                  onPressed: () => setState(() => _shown += 50),
                  child: Text('Show more (${rows.length - _shown} left)'),
                ),
            ]),
          ),
      ]),
    );
  }
}

/// Today / This Week / This Month / This Year, or a custom From-To range.
class _DateFilter extends StatelessWidget {
  final String from, to;
  final void Function(String from, String to) onChange;
  const _DateFilter({required this.from, required this.to, required this.onChange});

  Future<void> _pick(BuildContext context, bool isFrom) async {
    final current = DateTime.tryParse(isFrom ? from : to) ?? DateTime.parse(todayKey());
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: isFrom ? DateTime(2000) : (DateTime.tryParse(from) ?? DateTime(2000)),
      lastDate: isFrom ? (DateTime.tryParse(to) ?? DateTime(2100)) : DateTime(2100),
    );
    if (picked == null) return;
    isFrom ? onChange(dateKey(picked), to) : onChange(from, dateKey(picked));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    String? active;
    for (final (key, _) in _presets) {
      final r = _presetRange(key);
      if (r.$1 == from && r.$2 == to) active = key;
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 8, runSpacing: 4, children: [
          for (final (key, label) in _presets)
            ChoiceChip(
              label: Text(label),
              selected: active == key,
              onSelected: (_) {
                final r = _presetRange(key);
                onChange(r.$1, r.$2);
              },
            ),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _pick(context, true),
              icon: const Icon(Icons.event_rounded, size: 18),
              label: Text(from.isEmpty ? 'From' : rDate(from)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text('to', style: TextStyle(color: c.textTertiary, fontSize: 14)),
          ),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _pick(context, false),
              icon: const Icon(Icons.event_rounded, size: 18),
              label: Text(to.isEmpty ? 'To' : rDate(to)),
            ),
          ),
        ]),
        if (from.isNotEmpty || to.isNotEmpty)
          TextButton(
            onPressed: () => onChange('', ''),
            style: TextButton.styleFrom(foregroundColor: Colors.red.shade400),
            child: const Text('Clear'),
          ),
      ]),
    );
  }
}

/// The RPCPPE's report details: printed at the top of each form.
class _RpcppeDetails extends ConsumerStatefulWidget {
  final Map<String, String> settings;
  const _RpcppeDetails({required this.settings});

  @override
  ConsumerState<_RpcppeDetails> createState() => _RpcppeDetailsState();
}

class _RpcppeDetailsState extends ConsumerState<_RpcppeDetails> {
  late final Map<String, TextEditingController> _text = {
    for (final k in ['fundCluster', 'officer', 'designation', 'entity']) k: TextEditingController(text: widget.settings[k]),
  };

  @override
  void dispose() {
    for (final t in _text.values) {
      t.dispose();
    }
    super.dispose();
  }

  void _set(String key, String value) => ref.read(rpcppeSettingsProvider.notifier).set(key, value);

  Future<void> _pickDate(String key) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(widget.settings[key] ?? '') ?? DateTime.parse(todayKey()),
      firstDate: DateTime(1990),
      lastDate: DateTime(2100),
    );
    if (picked != null) _set(key, dateKey(picked));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = widget.settings;
    Widget date(String key, String label, String placeholder) => Padding(
          padding: const EdgeInsets.only(top: 10),
          child: InkWell(
            onTap: () => _pickDate(key),
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: label,
                suffixIcon: (s[key] ?? '').isNotEmpty && key == 'asAt'
                    ? IconButton(icon: const Icon(Icons.close_rounded), tooltip: 'Use today', onPressed: () => _set(key, ''))
                    : const Icon(Icons.event_rounded),
              ),
              child: Text((s[key] ?? '').isEmpty ? placeholder : longDate(s[key]),
                  style: TextStyle(color: (s[key] ?? '').isEmpty ? c.textTertiary : c.textPrimary, fontSize: 15)),
            ),
          ),
        );
    Widget text(String key, String label) => Padding(
          padding: const EdgeInsets.only(top: 10),
          child: TextField(
            controller: _text[key],
            decoration: InputDecoration(labelText: label),
            onChanged: (v) => _set(key, v),
          ),
        );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: ExpansionTile(
          title: Text('Report details', style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.w600, fontSize: 16)),
          subtitle: Text('Printed at the top of each form. Items acquired after the "as at" date are left out.',
              style: TextStyle(color: c.textTertiary, fontSize: 13)),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            date('asAt', 'As at', 'Today'),
            text('fundCluster', 'Fund cluster'),
            text('officer', 'Accountable officer'),
            text('designation', 'Designation'),
            text('entity', 'Entity / LGU'),
            date('assumedOn', 'Assumed accountability on', 'Not set'),
          ],
        ),
      ),
    );
  }
}
