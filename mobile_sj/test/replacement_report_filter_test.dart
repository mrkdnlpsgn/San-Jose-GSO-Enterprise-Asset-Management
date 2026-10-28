import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:san_jose_eam_mobile/core/theme/app_theme.dart';
import 'package:san_jose_eam_mobile/features/reports/provider/reports_provider.dart';
import 'package:san_jose_eam_mobile/features/reports/screens/report_preview_screen.dart';
import 'package:san_jose_eam_mobile/features/settings/provider/settings_provider.dart';

// The Replacement Forecast's "Replace in" filter, which Home's Budget & Planning cards open on.
Map<String, dynamic> _row(String replaceIn, String no) => {
      'replaceIn': replaceIn, 'propertyNumber': no, 'description': 'Laptop', 'category': 'ICT Equipment',
      'office': 'GSO', 'acquisitionDate': '2020-01-10', 'usefulLifeYears': 5, 'endOfLife': '2025-01-10',
      'reason': 'Past expected life', 'condition': 'SERVICEABLE', 'unitValue': 50000, 'estimatedCost': 55000,
    };

final _rows = [_row('NOW', 'A-1'), _row('NOW', 'A-2'), _row('2027', 'B-1'), _row('2028', 'C-1')];

Future<void> _pump(WidgetTester tester, {String? replaceIn}) async {
  tester.view.physicalSize = const Size(390, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      reportDataProvider.overrideWith((ref, id) async => _rows),
    ],
    child: MaterialApp(theme: AppTheme.light, home: ReportPreviewScreen(reportId: 'replacement', replaceIn: replaceIn)),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('opens on the year passed in, and the chips switch groups', (tester) async {
    await _pump(tester, replaceIn: '2027');
    expect(find.textContaining('1 record (of 4)', findRichText: true), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Now'));
    await tester.pumpAndSettle();
    expect(find.textContaining('2 records', findRichText: true), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'All'));
    await tester.pumpAndSettle();
    expect(find.textContaining('4 records', findRichText: true), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows everything when opened without a group', (tester) async {
    await _pump(tester);
    expect(find.textContaining('4 records', findRichText: true), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, '2028'), findsOneWidget);
  });
}
