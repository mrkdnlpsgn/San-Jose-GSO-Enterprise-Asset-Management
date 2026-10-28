import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/section_card.dart';
import '../../reports/utils/formatters.dart';
import '../data/return_papers_service.dart';
import '../model/return_papers_model.dart';
import '../utils/return_papers_pdf.dart';

/// "PARs & Return Slips" on the asset's details (the web's tab of the same name): one row per
/// end-user change - the old end user's return slip and the new one's PAR, each printable - and the
/// asset's original PAR under them. Shown only once the asset has any.
class ReturnPapersCard extends ConsumerWidget {
  final int assetId;
  const ReturnPapersCard({super.key, required this.assetId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final papers = ref.watch(returnPapersProvider(assetId)).valueOrNull;
    if (papers == null || papers.isEmpty) return const SizedBox.shrink();
    final c = context.colors;
    final rows = papers.rows;

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: SectionCard(
        title: 'PARs & Return Slips',
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                'Made each time this asset changed end user: the old one returns it on a Property Return Slip and the new one gets a new PAR.',
                style: TextStyle(color: c.textSecondary, fontSize: 14, height: 1.4),
              ),
            ),
            for (var i = 0; i < rows.length; i++) ...[
              Divider(height: 1, color: c.border),
              _PaperRowTile(row: rows[i]),
            ],
          ],
        ),
      ),
    );
  }
}

class _PaperRowTile extends StatefulWidget {
  final PaperRow row;
  const _PaperRowTile({required this.row});

  @override
  State<_PaperRowTile> createState() => _PaperRowTileState();
}

class _PaperRowTileState extends State<_PaperRowTile> {
  bool _printing = false;

  Future<void> _print(Future<void> Function() job) async {
    setState(() => _printing = true);
    try {
      await job();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not print: $e'), backgroundColor: Colors.red.shade800));
      }
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.row;
    final c = context.colors;
    final title = r.isOriginal
        ? 'Original PAR, issued to ${r.par!.personnelName ?? 'no end user'}'
        : '${r.slip?.returnedByName ?? 'No end user'} → ${r.par?.personnelName ?? 'no end user'}';
    final date = r.isOriginal ? r.par!.issueDate : (r.slip?.returnDate ?? r.par?.issueDate);
    final detail = [
      fmtDate(date),
      if (r.slip != null) 'Return Slip ${r.slip!.slipNumber}',
      if (r.par != null) 'PAR ${r.par!.parNumber}',
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: c.textPrimary, fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(detail, style: TextStyle(color: c.textTertiary, fontSize: 14)),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (r.slip != null)
              OutlinedButton.icon(
                icon: const Icon(Icons.print_outlined, size: 18),
                label: const Text('Return Slip'),
                onPressed: _printing ? null : () => _print(() => printReturnSlip(r.slip!)),
              ),
            if (r.par != null)
              OutlinedButton.icon(
                icon: const Icon(Icons.print_outlined, size: 18),
                label: const Text('PAR'),
                onPressed: _printing ? null : () => _print(() => printPar(r.par!)),
              ),
          ]),
        ],
      ),
    );
  }
}
