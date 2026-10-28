import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/skeleton.dart';
import '../provider/planning_provider.dart';
import 'ios_style.dart';

/// Home's "Budget & Planning" (admins only), the same as the web's and laid out for reading at a
/// glance, including by older staff: large figures with a plain label above each, money written
/// as "₱321.9 million" with the exact amount under it, and the coming years as a table with a
/// total. Breakdowns by type and the book-value figures live in the Replacement Forecast and
/// Depreciation Schedule reports.
class BudgetPlanningCard extends ConsumerStatefulWidget {
  const BudgetPlanningCard({super.key});

  @override
  ConsumerState<BudgetPlanningCard> createState() => _BudgetPlanningCardState();
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

/// ₱321,868,619.98 -> "₱321,868,620".
String _pesoExact(double v) => '₱${_count(v.round())}';

/// ₱321,868,619.98 -> "₱321.9 million"; smaller amounts in full, without centavos.
String _pesoWords(double v) {
  if (v >= 1000000000) return '₱${(v / 1000000000).toStringAsFixed(1)} billion';
  if (v >= 1000000) return '₱${(v / 1000000).toStringAsFixed(1)} million';
  return _pesoExact(v);
}

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
                  style: TextStyle(color: c.textSecondary, fontSize: 16))
              : const Shimmer(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Bone(width: double.infinity, height: 140),
                      SizedBox(height: 16),
                      Bone(width: 160, height: 16),
                      SizedBox(height: 10),
                      Bone(width: double.infinity, height: 120),
                    ],
                  ),
                ),
        ),
      );
    }

    final thisYear = p.asOf.length >= 4 ? p.asOf.substring(0, 4) : '';
    final dueNow = p.dueNow;
    final coming = p.coming;
    final comingAssets = coming.fold<int>(0, (n, b) => n + b.assets);
    final comingCost = coming.fold<double>(0, (n, b) => n + b.cost);
    final heading = TextStyle(fontSize: 18, fontWeight: FontWeight.w600, letterSpacing: -0.3, color: c.textPrimary);
    final body = TextStyle(fontSize: 16, height: 1.4, color: c.textPrimary);
    final note = TextStyle(fontSize: 15, height: 1.4, color: c.textSecondary);

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Assets that need replacing, and about how much it will cost. As of ${_longDate(p.asOf)}.', style: note),
            const SizedBox(height: 14),

            // 1. Due now
            if (dueNow != null && dueNow.assets > 0)
              Container(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                decoration: BoxDecoration(
                  color: Ios.orange.withValues(alpha: context.isLight ? 0.10 : 0.16),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Ios.orange.withValues(alpha: 0.45)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Due for replacement now', style: heading),
                    const SizedBox(height: 12),
                    _BigFigure(label: 'Number of assets', value: _count(dueNow.assets)),
                    const SizedBox(height: 14),
                    _BigFigure(
                      label: 'Estimated cost to replace',
                      value: _pesoWords(dueNow.cost),
                      exact: dueNow.cost >= 1000000 ? _pesoExact(dueNow.cost) : null,
                    ),
                    const SizedBox(height: 14),
                    Text('These assets are past their expected years of use, or broken and waiting for disposal.', style: body),
                    const SizedBox(height: 14),
                    FilledButton(
                      onPressed: () => context.push('/reports/replacement'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.brandButton,
                        minimumSize: const Size.fromHeight(48),
                        textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                      ),
                      child: const Text('See the list of assets'),
                    ),
                  ],
                ),
              )
            else
              Text('No assets are due for replacement right now.', style: body),

            // 2. The coming years, as a table with a total
            if (coming.isNotEmpty) ...[
              const SizedBox(height: 22),
              Text('Coming up in the next years', style: heading),
              const SizedBox(height: 6),
              _YearRow(
                year: 'Year',
                assets: 'Assets',
                cost: 'Estimated cost',
                style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: c.textSecondary),
              ),
              Divider(height: 2, thickness: 2, color: Ios.separator(context)),
              for (var i = 0; i < coming.length; i++) ...[
                if (i > 0) Divider(height: 1, thickness: 0.5, color: Ios.separator(context)),
                _YearRow(
                  year: coming[i].key == thisYear ? 'Rest of ${coming[i].key}' : coming[i].key,
                  assets: _count(coming[i].assets),
                  cost: _pesoWords(coming[i].cost),
                  style: TextStyle(fontSize: 17, color: c.textPrimary),
                  costBold: true,
                ),
              ],
              Divider(height: 2, thickness: 2, color: Ios.separator(context)),
              _YearRow(
                year: 'Total',
                assets: _count(comingAssets),
                cost: _pesoWords(comingCost),
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: c.textPrimary),
              ),
              const SizedBox(height: 4),
              Text('Costs include ${p.priceIncreasePercent.toStringAsFixed(0)}% a year for price increases.', style: note),
            ],

            if (p.noExpectedLife.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(
                'Not counted yet: ${p.noExpectedLife.join(', ')}. '
                '${p.noExpectedLife.length == 1 ? 'This type has' : 'These types have'} no expected years of use. '
                'Set it on the Categories page.',
                style: const TextStyle(fontSize: 16, height: 1.4, color: Ios.orange),
              ),
            ],

            // 3. Summary (AI)
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 14),
              decoration: BoxDecoration(
                color: Ios.groupedBg(context),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // the button moves under the heading when large text leaves no room beside it
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 12,
                    runSpacing: 4,
                    children: [
                      Text('Summary', style: heading),
                      _generating
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                            )
                          : OutlinedButton(
                              onPressed: _generate,
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(0, 44),
                                textStyle: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600),
                              ),
                              child: Text(p.summary != null ? 'Write again' : 'Write summary'),
                            ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text(
                      p.summary ??
                          (_generating
                              ? 'Writing the summary…'
                              : 'Press "Write summary" and the AI will explain these numbers in a few sentences.'),
                      style: p.summary != null ? body.copyWith(fontSize: 17, height: 1.5) : note.copyWith(fontSize: 16),
                    ),
                  ),
                ],
              ),
            ),

            // More detail lives in the reports
            const SizedBox(height: 12),
            Text('More detail:', style: note),
            Wrap(
              spacing: 16,
              children: [
                TextButton(
                  onPressed: () => context.push('/reports/replacement'),
                  style: TextButton.styleFrom(padding: EdgeInsets.zero, textStyle: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w600)),
                  child: const Text('Replacement Forecast'),
                ),
                TextButton(
                  onPressed: () => context.push('/reports/depreciation'),
                  style: TextButton.styleFrom(padding: EdgeInsets.zero, textStyle: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w600)),
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

/// One large figure with a plain label above it and, for big amounts, the exact amount below.
class _BigFigure extends StatelessWidget {
  final String label;
  final String value;
  final String? exact;
  const _BigFigure({required this.label, required this.value, this.exact});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.textSecondary)),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(value,
              style: TextStyle(fontSize: 32, height: 1.15, fontWeight: FontWeight.w700, letterSpacing: -0.5, color: c.textPrimary)),
        ),
        if (exact != null) Text('Exact: $exact', style: TextStyle(fontSize: 15, color: c.textSecondary)),
      ],
    );
  }
}

/// One row of the "Coming up" table: year on the left, asset count and cost right-aligned.
class _YearRow extends StatelessWidget {
  final String year;
  final String assets;
  final String cost;
  final TextStyle style;
  final bool costBold;
  const _YearRow({required this.year, required this.assets, required this.cost, required this.style, this.costBold = false});

  @override
  Widget build(BuildContext context) {
    final costStyle = costBold ? style.copyWith(fontWeight: FontWeight.w700) : style;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 4, child: Text(year, style: style)),
          Expanded(flex: 3, child: Text(assets, textAlign: TextAlign.right, style: style)),
          const SizedBox(width: 8),
          Expanded(flex: 5, child: Text(cost, textAlign: TextAlign.right, style: costStyle)),
        ],
      ),
    );
  }
}
