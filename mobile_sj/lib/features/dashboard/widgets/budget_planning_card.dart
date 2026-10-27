import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/skeleton.dart';
import '../provider/planning_provider.dart';
import 'ios_style.dart';

/// Home's "Budget & Planning" (admins only), the same as the web's and written for GSO staff
/// rather than accountants: one clear message first (what is due for replacement now, with a
/// link to the list), then the coming years and where most of the cost is. The book-value
/// figures for the Accounting Office and the "how is this counted" notes start folded.
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
    final comingAssets = coming.fold<int>(0, (n, b) => n + b.assets);
    final comingCost = coming.fold<double>(0, (n, b) => n + b.cost);
    final top = p.categories.take(3).toList();
    final maxCost = top.isEmpty || top.first.cost <= 0 ? 1.0 : top.first.cost;
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

            // 1. The one thing to know
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
                        const TextSpan(text: 'Replacing them would cost about '),
                        TextSpan(text: _short(dueNow.cost), style: const TextStyle(fontWeight: FontWeight.w700)),
                        const TextSpan(
                            text: '. They have been used longer than expected, or they are broken and waiting for disposal.'),
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

            // 2. The coming years
            const SizedBox(height: 20),
            Text('Coming up', style: heading),
            const SizedBox(height: 2),
            Text(
                'Assets that will reach the end of their expected years of use. '
                'Total: ${_short(comingCost)} for ${_plural(comingAssets, 'asset', 'assets')}.',
                style: note),
            const SizedBox(height: 10),
            // Two per row, each row as tall as its tallest tile, so larger text sizes still fit.
            for (var i = 0; i < coming.length; i += 2) ...[
              if (i > 0) const SizedBox(height: 10),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final b in coming.skip(i).take(2)) ...[
                      if (b != coming[i]) const SizedBox(width: 10),
                      Expanded(
                        child: _Figure(
                          label: b.key == thisYear ? 'Rest of ${b.key}' : b.key,
                          value: _short(b.cost),
                          sub: _plural(b.assets, 'asset', 'assets'),
                        ),
                      ),
                    ],
                    if (i + 1 >= coming.length) ...[const SizedBox(width: 10), const Expanded(child: SizedBox())],
                  ],
                ),
              ),
            ],

            // 3. Where the money goes
            if (top.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text('Where most of the cost is', style: heading),
              const SizedBox(height: 2),
              Text('Types of assets with the highest replacement cost, due now and coming up.', style: note),
              const SizedBox(height: 10),
              for (var i = 0; i < top.length; i++) ...[
                if (i > 0) const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Text(top[i].name,
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 16, color: c.textPrimary)),
                    ),
                    const SizedBox(width: 8),
                    Text(_short(top[i].cost),
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: c.textPrimary)),
                  ],
                ),
                Text('for ${_plural(top[i].assets, 'asset', 'assets')}', style: TextStyle(fontSize: 13.5, color: c.textSecondary)),
                const SizedBox(height: 5),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: Container(
                    height: 6,
                    color: c.border.withValues(alpha: 0.5),
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: (top[i].cost / maxCost).clamp(0.0, 1.0),
                      child: Container(
                          decoration: BoxDecoration(color: AppTheme.brand, borderRadius: BorderRadius.circular(3))),
                    ),
                  ),
                ),
              ],
            ],

            if (p.noExpectedLife.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                'Not counted yet: ${p.noExpectedLife.join(', ')}. '
                '${p.noExpectedLife.length == 1 ? 'This type has' : 'These types have'} no expected years of use. '
                'Set it on the Categories page.',
                style: const TextStyle(fontSize: 14.5, height: 1.4, color: Ios.orange),
              ),
            ],

            // 4. Summary in plain words (AI)
            const SizedBox(height: 18),
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
                      Expanded(child: Text('Summary in plain words', style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600, color: c.textPrimary))),
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
                          (_generating
                              ? 'Writing the summary…'
                              : 'The AI can explain these numbers in a few sentences, for reports and meetings.'),
                      style: TextStyle(
                          fontSize: p.summary != null ? 16 : 15,
                          height: 1.45,
                          color: p.summary != null ? c.textPrimary : c.textSecondary),
                    ),
                  ),
                ],
              ),
            ),

            // 5. Folded away until opened
            const SizedBox(height: 8),
            _Fold(
              title: 'Asset value, for the Accounting Office',
              children: [
                Text('What the assets are worth on the books after wear and tear. The full table is in the '
                    'Depreciation Schedule report.', style: note),
                const SizedBox(height: 10),
                _Figure(label: 'What we paid for them', value: _short(p.totalCost),
                    sub: _plural(p.assets, 'asset', 'assets'), term: 'Total cost'),
                const SizedBox(height: 8),
                _Figure(label: 'What they are worth today', value: _short(p.bookValue),
                    sub: 'After wear and tear', term: 'Book value'),
                const SizedBox(height: 8),
                _Figure(
                    label: 'Value lost so far',
                    value: _short(p.accumulatedDepreciation),
                    sub: p.totalCost > 0
                        ? '${(p.accumulatedDepreciation * 100 / p.totalCost).round()}% of what we paid'
                        : null,
                    term: 'Accumulated depreciation'),
                const SizedBox(height: 8),
                _Figure(label: 'Value lost this year ($thisYear)', value: _short(p.depreciationExpense),
                    sub: 'About ${_short(p.monthlyDepreciation)} a month', term: 'Depreciation expense'),
                const SizedBox(height: 10),
                Text(
                  '${_plural(p.fullyDepreciated, 'asset has', 'assets have')} reached the end of '
                  '${p.fullyDepreciated == 1 ? 'its' : 'their'} counted value. Only the 5% minimum value is left on '
                  'the books (fully depreciated).',
                  style: TextStyle(fontSize: 15, height: 1.4, color: c.textPrimary),
                ),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () => context.push('/reports/depreciation'),
                    child: const Text('Open the Depreciation Schedule'),
                  ),
                ),
              ],
            ),
            _Fold(
              title: 'How these numbers are worked out',
              children: [
                for (final line in [
                  'Each type of asset has an expected number of years of use, set on the Categories page (for example, 5 years for ICT Equipment).',
                  'Due now means the asset has passed its expected years of use, or it is unserviceable and waiting for disposal.',
                  'Replacement cost is what was paid for the asset, plus ${p.priceIncreasePercent.toStringAsFixed(0)}% a year for price increases.',
                  "Value on the books goes down by the same amount every month until only 5% of the cost is left (straight-line depreciation, as in the Accounting Office's schedule).",
                ])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('•  ', style: TextStyle(fontSize: 15, height: 1.4, color: c.textSecondary)),
                        Expanded(child: Text(line, style: TextStyle(fontSize: 15, height: 1.4, color: c.textPrimary))),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// One figure in a small bordered box; [term] is the official (accounting) name, shown small.
class _Figure extends StatelessWidget {
  final String label;
  final String value;
  final String? sub;
  final String? term;
  const _Figure({required this.label, required this.value, this.sub, this.term});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Ios.separator(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, color: c.textSecondary)),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value,
                style: TextStyle(fontSize: 21, height: 1.15, fontWeight: FontWeight.w700, letterSpacing: -0.5, color: c.textPrimary)),
          ),
          if (sub != null) Text(sub!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: c.textSecondary)),
          if (term != null) ...[
            const SizedBox(height: 2),
            Text('Official term: $term', style: TextStyle(fontSize: 12.5, color: c.textTertiary)),
          ],
        ],
      ),
    );
  }
}

/// A section that starts closed (iOS-style disclosure row).
class _Fold extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _Fold({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Theme(
      // no extra divider lines above and below an opened section
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 10),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        title: Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: c.textPrimary)),
        iconColor: c.textSecondary,
        collapsedIconColor: c.textTertiary,
        children: children,
      ),
    );
  }
}
