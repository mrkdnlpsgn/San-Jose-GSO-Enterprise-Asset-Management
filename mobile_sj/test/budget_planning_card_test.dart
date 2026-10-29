import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
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
      'maintenance': {
        'years': [
          {'year': 2023, 'cost': 1850000, 'records': 120, 'assets': 95, 'soFar': false},
          {'year': 2024, 'cost': 2100000, 'records': 131, 'assets': 101, 'soFar': false},
          {'year': 2025, 'cost': 2450000.5, 'records': 140, 'assets': 110, 'soFar': false},
          {'year': 2026, 'cost': 1720000, 'records': 98, 'assets': 80, 'soFar': true},
        ],
        'forecast': {'year': 2027, 'cost': 2335000},
        'trend': 'RISING',
        'priceIncreasePercent': 3.0,
        'limitedHistory': false,
        'byCategory': [
          {'category': 'Motor Vehicle', 'forecast': 1400000},
        ],
        'accuracy': {
          'years': [
            {'year': 2024, 'estimate': 1610000, 'actual': 2100000, 'errorPercent': -23.3},
            {'year': 2025, 'estimate': 1980000, 'actual': 2450000.5, 'errorPercent': -19.2},
          ],
          'averageErrorPercent': 21.3,
        },
      },
      'repairRisk': {
        'notEnoughHistory': false,
        'expectedAssets': 121,
        'high': 43,
        'medium': 87,
        'check': {'year': 2025, 'assets': 1536, 'needed': 119, 'expected': 89, 'found': 55, 'foundPercent': 46.2, 'randomPercent': 7.7, 'auc': 0.78},
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
  testWidgets('a year card and the due-now button open the forecast on that group', (tester) async {
    tester.view.physicalSize = const Size(390, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final router = GoRouter(routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => const Scaffold(body: SingleChildScrollView(padding: EdgeInsets.all(16), child: BudgetPlanningCard())),
      ),
      GoRoute(
        path: '/reports/:id',
        builder: (_, s) => Scaffold(body: Text('opened ${s.pathParameters['id']} ${s.uri.queryParameters['replaceIn']}')),
      ),
    ]);
    await tester.pumpWidget(ProviderScope(
      overrides: [planningProvider.overrideWith((ref) async => _planning())],
      child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('2027'));
    await tester.pumpAndSettle();
    expect(find.text('opened replacement 2027'), findsOneWidget);

    router.pop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('See the list of assets'));
    await tester.pumpAndSettle();
    expect(find.text('opened replacement NOW'), findsOneWidget);
  });

  testWidgets('leads with what is due now, in plain words', (tester) async {
    await _pump(tester, _planning(), theme: AppTheme.light);
    expect(find.text('Due for replacement now'), findsOneWidget);
    expect(find.text('810'), findsOneWidget);
    expect(find.text('₱321.9 million'), findsOneWidget);
    expect(find.text('Exact: ₱321,868,620'), findsOneWidget);
    expect(find.text('See the list of assets'), findsOneWidget);
    expect(find.text('Needs budget'), findsOneWidget);
    // one card per coming year
    expect(find.text('Rest of 2026'), findsOneWidget);
    expect(find.text('2029'), findsOneWidget);
    expect(find.text('₱20.8 million'), findsOneWidget);
    expect(find.text('46 assets'), findsOneWidget);
    expect(find.text('View assets'), findsNWidgets(4));
    // total of 46 + 222 + 201 + 184 assets
    expect(find.textContaining('₱254.8 million for 653 assets', findRichText: true), findsOneWidget);
    expect(find.text('Write summary'), findsOneWidget);
    // breakdowns by type and accounting figures are in the reports, not on Home
    expect(find.text('Motor Vehicle'), findsNothing);
    expect(find.text('Depreciation Schedule'), findsOneWidget);
    expect(find.textContaining('Costs include 3% a year'), findsOneWidget);
  });

  testWidgets('shows repair and maintenance spending and the estimate for next year', (tester) async {
    tester.view.physicalSize = const Size(390, 4400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final router = GoRouter(routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => const Scaffold(body: SingleChildScrollView(padding: EdgeInsets.all(16), child: BudgetPlanningCard())),
      ),
      GoRoute(path: '/reports/:id', builder: (_, s) => Scaffold(body: Text('opened ${s.pathParameters['id']}'))),
    ]);
    await tester.pumpWidget(ProviderScope(
      overrides: [planningProvider.overrideWith((ref) async => _planning())],
      child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Repairs and maintenance'), findsOneWidget);
    expect(find.text('Rising'), findsOneWidget);
    expect(find.text('Estimated budget for 2027'), findsOneWidget);
    expect(find.text('₱2.3 million'), findsOneWidget);
    expect(find.text('Exact: ₱2,335,000'), findsOneWidget);
    expect(find.text('2026 (so far)'), findsOneWidget);
    expect(find.text('₱2.5 million'), findsOneWidget); // 2025
    expect(find.textContaining('Costs most to keep running: Motor Vehicle'), findsOneWidget);

    // the check against past years opens to show each year
    expect(find.textContaining('this method was off by about 21.3% on average', findRichText: true), findsOneWidget);
    expect(find.text('2024: 23.3% too low'), findsNothing);
    await tester.ensureVisible(find.textContaining('this method was off by about', findRichText: true));
    await tester.tap(find.textContaining('this method was off by about', findRichText: true));
    await tester.pumpAndSettle();
    expect(find.text('2024: 23.3% too low'), findsOneWidget);
    expect(find.text('Estimate ₱1.6 million, actual ₱2.1 million'), findsOneWidget);

    // the machine-learning repair risk, in plain words, with how it was tested
    expect(find.text('AI forecast: assets likely to need repair this coming year'), findsOneWidget);
    expect(find.text('About 121 assets'), findsOneWidget);
    expect(find.text('43 assets'), findsOneWidget);
    expect(find.textContaining('43 assets are very likely to need repair, and 87 more might'), findsOneWidget);
    expect(find.textContaining('it had named 46 in advance', findRichText: true), findsNothing);
    await tester.ensureVisible(find.text('How does the system know?'));
    await tester.tap(find.text('How does the system know?'));
    await tester.pumpAndSettle();
    expect(find.textContaining('it had named 46 in advance. Guessing would name only 8.', findRichText: true), findsOneWidget);
    await tester.ensureVisible(find.text('See the list'));
    await tester.tap(find.text('See the list'));
    await tester.pumpAndSettle();
    expect(find.text('opened repairrisk'), findsOneWidget);
    router.pop();
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('See by type of property'));
    await tester.tap(find.text('See by type of property'));
    await tester.pumpAndSettle();
    expect(find.text('opened maintenanceforecast'), findsOneWidget);
  });

  testWidgets('fits at phone width in dark mode, with a summary and a missing type', (tester) async {
    await _pump(tester, _planning(summary: 'A short note.', noLife: ['Office Supplies']), theme: AppTheme.dark);
    expect(find.text('A short note.'), findsOneWidget);
    expect(find.textContaining('Not counted yet: Office Supplies'), findsOneWidget);
    expect(find.text('Write again'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('fits a small phone with the largest text size', (tester) async {
    tester.view.physicalSize = const Size(320, 3600);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(ProviderScope(
      overrides: [planningProvider.overrideWith((ref) async => _planning())],
      child: MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(body: SingleChildScrollView(padding: EdgeInsets.all(16), child: BudgetPlanningCard())),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('₱321.9 million'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
