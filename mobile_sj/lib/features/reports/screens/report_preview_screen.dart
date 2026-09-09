import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../model/report_definition.dart';
import '../provider/reports_provider.dart';
import '../utils/export_excel.dart';
import '../utils/export_pdf.dart';
import '../../../shared/widgets/error_state.dart';

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
            onPressed: () => ref.invalidate(reportDataProvider(widget.reportId)),
          ),
        ],
      ),
      body: dataAsync.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppTheme.brand)),
        error: (e, _) => ErrorState(
          message: 'Failed to load report: $e',
          onRetry: () => ref.invalidate(reportDataProvider(widget.reportId)),
        ),
        data: (rows) {
          if (rows.isEmpty) {
            return Center(
              child: Text('No data available for this report.', style: TextStyle(color: context.colors.textSecondary)),
            );
          }

          final preview = rows;
          final isNarrow = MediaQuery.sizeOf(context).width < _kNarrowBreakpoint;

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(
                  children: [
                    Text('${rows.length} ${rows.length == 1 ? 'record' : 'records'}',
                        style: TextStyle(color: context.colors.textSecondary, fontWeight: FontWeight.w600, fontSize: 14)),
                  ],
                ),
              ),
              Expanded(
                child: isNarrow
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
                                            fontSize: 12))))
                                .toList(),
                            rows: preview
                                .map((row) => DataRow(
                                      cells: report.columns
                                          .map((c) => DataCell(Text(c.valueOf(row),
                                              style: TextStyle(color: context.colors.textSecondary, fontSize: 12))))
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
                            icon: const Icon(Icons.grid_on_rounded, size: 18, color: Colors.greenAccent),
                            label: const Text('Export Excel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _exporting ? null : () => _export(() => exportPdf(report, rows)),
                            icon: const Icon(Icons.picture_as_pdf_outlined, size: 18, color: Colors.redAccent),
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: columns
              .map((c) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 120,
                          child: Text(c.label,
                              style: TextStyle(
                                  color: context.colors.textTertiary, fontSize: 11, fontWeight: FontWeight.w600)),
                        ),
                        Expanded(
                          child: Text(c.valueOf(row), style: TextStyle(color: context.colors.textPrimary, fontSize: 13)),
                        ),
                      ],
                    ),
                  ))
              .toList(),
        ),
      ),
    );
  }
}
