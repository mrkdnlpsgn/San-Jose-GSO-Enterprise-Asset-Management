import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../model/report_definition.dart';
import '../provider/reports_provider.dart';

class ReportsListScreen extends ConsumerWidget {
  const ReportsListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reports = ref.watch(reportDefinitionsProvider);
    final c = context.colors;

    return Scaffold(
      appBar: AppBar(title: const Text('Reports')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Text('Choose a report to preview it, then export it to Excel or PDF.',
              style: TextStyle(color: c.textSecondary, fontSize: 15, height: 1.45)),
          const SizedBox(height: 16),
          // one bordered list, like the Dashboard's modules and the web Reports page
          Card(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < reports.length; i++) ...[
                  if (i > 0) Divider(height: 1, indent: 68, color: c.border),
                  _ReportRow(report: reports[i], onTap: () => context.push('/reports/${reports[i].id}')),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportRow extends StatelessWidget {
  final ReportDefinition report;
  final VoidCallback onTap;
  const _ReportRow({required this.report, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 72),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: c.subtle,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: c.border),
                ),
                child: Icon(report.icon, size: 21, color: c.heading),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(report.title, style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.w600, fontSize: 16)),
                    const SizedBox(height: 2),
                    Text(report.subtitle,
                        style: TextStyle(color: c.textTertiary, fontSize: 14, height: 1.35),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: c.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}
