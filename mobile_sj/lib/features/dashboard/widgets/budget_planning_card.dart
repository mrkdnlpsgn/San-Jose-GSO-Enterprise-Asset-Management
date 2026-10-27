import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/skeleton.dart';
import '../provider/planning_provider.dart';
import 'ios_style.dart';

/// Home's "Budget & Planning" (admins only), the same as the web's and kept short for GSO staff:
/// what is due for replacement now, what comes due in the next few years, and an optional AI
/// summary. Breakdowns by type and the book-value figures live in the Replacement Forecast and
/// Depreciation Schedule reports.
class BudgetPlanningCard extends ConsumerStatefulWidget {
  const BudgetPlanningCard({super.key});

  @override
  ConsumerState<BudgetPlanningCard> createState() => _BudgetPlanningCardState();
}

/// ₱321,912,345 -> "₱321.9M", ₱20,800 -> "₱21K" (the web's short form, for planning figures).
String _short(double v) {
  if (v >= 1000000) return '₱${(v / 1000000).toStringAsFixed(1)}M';
  if (v >= 1000) return '₱${(v / 1000).toStringAsFixed(0)}K';
  return '₱${v.toStringAsFixed(2)}';
}

String _count(int n) {
  final s = n.toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return buf.toString();
}

String _plural(int n, String one, String many) => '${_count(n)} ${n == 1 ? one : many}';

const _monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December'
];

String _longDate(String key) {
  final d = DateTime.tryParse(key);
  return d == null ? key : '${_monthNames[d.month - 1]} ${d.day}, ${d.year}';
}

class _BudgetPlanningCardState extends ConsumerState<BudgetPlanningCard> {
  bool _generating = false;
  Planning? _last; // keep showing the last numbers while a refresh is in flight

  Future<void> _generate() async {
    setState(() => _generating = true);
    try {
      await PlanningService().generate();
      // the summary is saved with the numbers, so a fresh read now returns it
      ref.invalidate(planningProvider);
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

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final async = ref.watch(planningProvider);
    if (async.hasValue) _last = async.value;
    final p = _last;

    if (p == null) {
      return Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: async.hasError
              ? Text("Couldn't load the budget and planning figures. Pull down to try again.",
                  style: TextStyle(color: c.textSecondary, fontSize: 15))
              : const Shimmer(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Bone(width: double.infinity, height: 72),
                      SizedBox(height: 16),
                      Bone(width: 140, height: 14),
                      SizedBox(height: 10),
                      Bone(width: double.infinity, height: 60),
                    ],
                  ),
                ),
        ),
      );
    }

    final thisYear = p.asOf.length >= 4 ? p.asOf.substring(0, 4) : '';
    final dueNow = p.dueNow;
    final coming = p.coming;
    final heading = TextStyle(fontSize: 17, fontWeight: FontWeight.w600, letterSpacing: -0.3, color: c.textPrimary);
    final note = TextStyle(fontSize: 14.5, height: 1.4, color: c.textSecondary);

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Which assets are getting old, and about how much replacing them will cost. As of ${_longDate(p.asOf)}.',
                style: note),
            const SizedBox(height: 14),

            // 1. Due now
            if (dueNow != null && dueNow.assets > 0)
              Container(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                decoration: BoxDecoration(
                  color: Ios.orange.withValues(alpha: context.isLight ? 0.10 : 0.16),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Ios.orange.withValues(alpha: 0.45)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('${_plural(dueNow.assets, 'asset is', 'assets are')} due for replacement now',
                        style: TextStyle(fontSize: 18, height: 1.25, fontWeight: FontWeight.w700, letterSpacing: -0.4, color: c.textPrimary)),
                    const SizedBox(height: 4),
                    Text.rich(
                      TextSpan(children: [
                        const TextSpan(text: 'About '),
                        TextSpan(text: _short(dueNow.cost), style: const TextStyle(fontWeight: FontWeight.w700)),
                        const TextSpan(text: ' to replace. They are past their expected years of use, or broken.'),
                      ]),
                      style: TextStyle(fontSize: 15, height: 1.4, color: c.textPrimary),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () => context.push('/reports/replacement'),
                      style: FilledButton.styleFrom(backgroundColor: AppTheme.brandButton, minimumSize: const Size.fromHeight(44)),
                      child: const Text('See the list'),
                    ),
                  ],
                ),
              )
            else
              Text('No assets are due for replacement right now.', style: TextStyle(fontSize: 15, color: c.textPrimary)),

            // 2. The coming years, one line each
            if (coming.isNotEmpty) ...[
              const SizedBox(height: 18),
              Text('Coming up', style: heading),
              const SizedBox(height: 4),
              for (var i = 0; i < coming.length; i++) ...[
                if (i > 0) Divider(height: 1, thickness: 0.5, color: Ios.separator(context)),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(coming[i].key == thisYear ? 'Rest of ${coming[i].key}' : coming[i].key,
                            style: TextStyle(fontSize: 16, color: c.textPrimary)),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(_short(coming[i].cost),
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: c.textPrimary)),
                          Text('for ${_plural(coming[i].assets, 'asset', 'assets')}',
                              style: TextStyle(fontSize: 13.5, color: c.textSecondary)),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ],

            if (p.noExpectedLife.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Not counted yet: ${p.noExpectedLife.join(', ')}. '
                '${p.noExpectedLife.length == 1 ? 'This type has' : 'These types have'} no expected years of use. '
                'Set it on the Categories page.',
                style: const TextStyle(fontSize: 14.5, height: 1.4, color: Ios.orange),
              ),
            ],

            // 3. Summary (AI)
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.fromLTRB(14, 6, 6, 12),
              decoration: BoxDecoration(
                color: Ios.groupedBg(context),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text('Summary', style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600, color: c.textPrimary))),
                      _generating
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                            )
                          : TextButton(onPressed: _generate, child: Text(p.summary != null ? 'Write again' : 'Write summary')),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text(
                      p.summary ??
                          (_generating ? 'Writing the summary…' : 'The AI can explain these numbers in a few sentences.'),
                      style: TextStyle(
                          fontSize: p.summary != null ? 16 : 15,
                          height: 1.45,
                          color: p.summary != null ? c.textPrimary : c.textSecondary),
                    ),
                  ),
                ],
              ),
            ),

            // More detail lives in the reports
            const SizedBox(height: 12),
            Text('Costs include ${p.priceIncreasePercent.toStringAsFixed(0)}% a year for price increases.', style: note),
            Wrap(
              spacing: 16,
              children: [
                TextButton(
                  onPressed: () => context.push('/reports/replacement'),
                  style: TextButton.styleFrom(padding: EdgeInsets.zero),
                  child: const Text('Replacement Forecast'),
                ),
                TextButton(
                  onPressed: () => context.push('/reports/depreciation'),
                  style: TextButton.styleFrom(padding: EdgeInsets.zero),
                  child: const Text('Depreciation Schedule'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
