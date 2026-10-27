import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:san_jose_eam_mobile/core/theme/app_theme.dart';
import 'package:san_jose_eam_mobile/features/dashboard/provider/planning_provider.dart';
import 'package:san_jose_eam_mobile/features/dashboard/widgets/budget_planning_card.dart';

// Home's Budget & Planning card at phone width, with figures like the live system's.
Planning _planning({String? summary, List<String> noLife = const []}) => Planning.fromJson({
      'replacement': {
        'asOf': '2026-10-28',
        'years': 3,
        'priceIncreasePercent': 3.0,
        'buckets': [
          {'key': 'NOW', 'assets': 810, 'cost': 321868619.98},
          {'key': '2026', 'assets': 46, 'cost': 20829649.6},
          {'key': '2027', 'assets': 222, 'cost': 82281687.78},
          {'key': '2028', 'assets': 201, 'cost': 74163777.84},
          {'key': '2029', 'assets': 184, 'cost': 77500559.78},
        ],
        'byCategory': [
          {'category': 'Motor Vehicle', 'assets': 151, 'cost': 261100000},
          {'category': 'Heavy Equipment', 'assets': 111, 'cost': 248900000},
          {'category': 'Disaster & Rescue Equipment with a long name', 'assets': 225, 'cost': 24700000},
          {'category': 'ICT Equipment', 'assets': 160, 'cost': 8700000},
        ],
        'excluded': {'noExpectedLife': noLife},
      },
      'depreciation': {
        'asOf': '2026-10-28',
        'total': {
          'assets': 2422, 'fullyDepreciated': 552, 'totalCost': 731663531.18, 'bookValue': 291806661.79,
          'accumulatedDepreciation': 439856869.39, 'depreciationExpense': 53890534.72, 'monthlyDepreciation': 5201969.8,
        },
      },
      'summary': summary,
    });

Future<void> _pump(WidgetTester tester, Planning p, {required ThemeData theme}) async {
  tester.view.physicalSize = const Size(390, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [planningProvider.overrideWith((ref) async => p)],
    child: MaterialApp(
      theme: theme,
      home: const Scaffold(body: SingleChildScrollView(padding: EdgeInsets.all(16), child: BudgetPlanningCard())),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('leads with what is due now, in plain words', (tester) async {
    await _pump(tester, _planning(), theme: AppTheme.light);
    expect(find.text('810 assets are due for replacement now'), findsOneWidget);
    expect(find.text('See the list'), findsOneWidget);
    expect(find.text('Rest of 2026'), findsOneWidget);
    expect(find.text('2029'), findsOneWidget);
    expect(find.textContaining('About ₱321.9M', findRichText: true), findsOneWidget);
    expect(find.text('₱20.8M'), findsOneWidget);
    expect(find.text('for 46 assets'), findsOneWidget);
    expect(find.text('Write summary'), findsOneWidget);
    // breakdowns by type and accounting figures are in the reports, not on Home
    expect(find.text('Motor Vehicle'), findsNothing);
    expect(find.text('Depreciation Schedule'), findsOneWidget);
    expect(find.textContaining('3% a year'), findsOneWidget);
  });

  testWidgets('fits at phone width in dark mode, with a summary and a missing type', (tester) async {
    await _pump(tester, _planning(summary: 'A short note.', noLife: ['Office Supplies']), theme: AppTheme.dark);
    expect(find.text('A short note.'), findsOneWidget);
    expect(find.textContaining('Not counted yet: Office Supplies'), findsOneWidget);
    expect(find.text('Write again'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
