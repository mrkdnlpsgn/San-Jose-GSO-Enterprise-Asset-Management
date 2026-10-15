import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../model/report_definition.dart';
import '../provider/reports_provider.dart';
import '../utils/export_excel.dart';
import '../utils/export_pdf.dart';
import '../../../shared/widgets/error_state.dart';
import '../../assets/model/asset_model.dart';
import '../../assets/widgets/asset_group_widgets.dart';
import 'package:go_router/go_router.dart';

const _kNarrowBreakpoint = 600.0;

class ReportPreviewScreen extends ConsumerStatefulWidget {
  final String reportId;
  const ReportPreviewScreen({super.key, required this.reportId});

  @override
  ConsumerState<ReportPreviewScreen> createState() => _ReportPreviewScreenState();
}

class _ReportPreviewScreenState extends ConsumerState<ReportPreviewScreen> {
  bool _exporting = false;

  Future<void> _export(Future<void> Function() action) async {
    setState(() => _exporting = true);
    try {
      await action();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Export ready.'),
          behavior: SnackBarBehavior.floating,
        ));
      }
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

  @override
  Widget build(BuildContext context) {
    final report = ref.watch(reportDefinitionsProvider).firstWhere((r) => r.id == widget.reportId);
    final dataAsync = ref.watch(reportDataProvider(widget.reportId));

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
          message: 'Failed to load report: $e',
          onRetry: () => ref.invalidate(reportDataProvider(widget.reportId)),
        ),
        data: (rows) {
          if (rows.isEmpty) {
            return Center(
              child: Text('No data available for this report.',
                  style: TextStyle(color: context.colors.textSecondary, fontSize: 15)),
            );
          }

          final preview = rows;
          final isNarrow = MediaQuery.sizeOf(context).width < _kNarrowBreakpoint;

          // Rows whose device belongs to a group (same model) collapse into one expandable card;
          // exports still list every device on its own row. Summary/aggregate rows aren't per-device.
          final entries = groupRecords<dynamic>(preview, (row) => _assetOf(row)?.groupId);
          final hasGroups = entries.any((e) => e.isGroup);

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(
                  children: [
                    Text('${rows.length} ${rows.length == 1 ? 'record' : 'records'}',
                        style: TextStyle(color: context.colors.textSecondary, fontWeight: FontWeight.w700, fontSize: 15)),
                  ],
                ),
              ),
              Expanded(
                child: hasGroups
                    ? ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        itemCount: entries.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, i) {
                          final entry = entries[i];
                          if (!entry.isGroup) return _ReportRowCard(row: entry.members.first, columns: report.columns);
                          return RecordGroupCard<dynamic>(
                            members: entry.members,
                            assetOf: _assetOf,
                            noun: 'rows',
                            columns: [for (final c in report.columns) c.label],
                            values: (row) => [for (final c in report.columns) c.valueOf(row)],
                            onOpenDevice: (a) => context.push('/assets/${a.id}'),
                          );
                        },
                      )
                    : isNarrow
                    ? ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        itemCount: preview.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, i) => _ReportRowCard(row: preview[i], columns: report.columns),
                      )
                    : SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        scrollDirection: Axis.horizontal,
                        child: SingleChildScrollView(
                          child: DataTable(
                            headingRowColor: WidgetStateProperty.all(context.colors.surface),
                            columns: report.columns
                                .map((c) => DataColumn(
                                    label: Text(c.label,
                                        style: TextStyle(
                                            color: context.colors.textTertiary,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 14))))
                                .toList(),
                            rows: preview
                                .map((row) => DataRow(
                                      cells: report.columns
                                          .map((c) => DataCell(Text(c.valueOf(row),
                                              style: TextStyle(color: context.colors.textSecondary, fontSize: 14))))
                                          .toList(),
                                    ))
                                .toList(),
                          ),
                        ),
                      ),
              ),
              if (_exporting) const LinearProgressIndicator(color: AppTheme.brand),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: context.colors.surface,
                  border: Border(top: BorderSide(color: context.colors.border)),
                ),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _exporting ? null : () => _export(() => exportExcel(report, rows)),
                            icon: const Icon(Icons.grid_on_rounded, size: 20),
                            label: const Text('Excel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _exporting ? null : () => _export(() => exportPdf(report, rows)),
                            icon: const Icon(Icons.print_rounded, size: 20),
                            label: const Text('Print / PDF'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Card-per-row fallback for phone-width screens, where a wide DataTable
/// forces cramped double-scrolling. Same columns, stacked as label/value pairs.
class _ReportRowCard extends StatelessWidget {
  final dynamic row;
  final List<ReportColumn> columns;
  const _ReportRowCard({required this.row, required this.columns});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < columns.length; i++) ...[
            if (i > 0) Divider(height: 1, indent: 14, color: c.border),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 4,
                    child: Text(columns[i].label, style: TextStyle(color: c.textTertiary, fontSize: 14)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 6,
                    child: Text(columns[i].valueOf(row),
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          color: c.textPrimary,
                          fontSize: 15,
                          fontWeight: i == 0 ? FontWeight.w700 : FontWeight.w500,
                        )),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// The device a report row is about: the row itself for asset reports, its nested `asset` for
// maintenance / disposal / history reports, none for summary rows.
AssetModel? _assetOf(dynamic row) {
  if (row is AssetModel) return row;
  if (row is Map) return null;
  try {
    final a = row.asset;
    return a is AssetModel ? a : null;
  } catch (_) {
    return null;
  }
}
