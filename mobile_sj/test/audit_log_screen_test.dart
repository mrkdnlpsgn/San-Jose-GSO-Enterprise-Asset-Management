import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:san_jose_eam_mobile/core/theme/app_theme.dart';
import 'package:san_jose_eam_mobile/features/audit_log/data/audit_log_service.dart';
import 'package:san_jose_eam_mobile/features/audit_log/model/audit_log_model.dart';
import 'package:san_jose_eam_mobile/features/audit_log/screens/audit_log_screen.dart';

AuditLogModel _log(int id, String action, String module, String details, DateTime when, {String? name}) =>
    AuditLogModel.fromJson({
      'id': id,
      'action': action,
      'module': module,
      'details': details,
      'targetType': 'asset',
      'targetId': 7,
      'loggedAt': when.toUtc().toIso8601String(),
      'user': {'username': 'admin', 'fullName': name},
    });

class _FakeService implements AuditLogService {
  @override
  Future<AuditArchiveSummary> archiveSummary() async => AuditArchiveSummary.fromJson({
        'retentionDays': 365,
        'liveCount': 3,
        'archivedCount': 12,
        'archivedOldest': '2024-03-01T02:00:00Z',
        'archivedNewest': '2025-01-10T05:00:00Z',
      });

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final now = DateTime.now();
  final logs = [
    _log(3, 'MAINTENANCE_UPDATED', 'Maintenance', 'Updated maintenance for asset: COA-2017-901', now,
        name: 'GSO Administrator'),
    _log(2, 'AI_RECOMMENDATION_GENERATED', 'Assets',
        'Generated AI recommendation for COA-2016-902: BUDGET_PRIORITY — a long description that wraps', now),
    _log(1, 'ASSET_TRANSFERRED', 'Assets', 'Transferred COA-2017-903 to MTO', DateTime(2026, 3, 4, 9, 5)),
  ];

  Future<void> pump(WidgetTester tester, {double textScale = 1}) async {
    tester.view.physicalSize = const Size(360 * 3, 720 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        auditLogsProvider.overrideWith((ref) async => logs),
        auditLogServiceProvider.overrideWithValue(_FakeService()),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: const AuditLogScreen(),
      ),
    ));
    await tester.pumpAndSettle();
  }

  test('action labels read as plain words', () {
    expect(logs[0].actionLabel, 'Maintenance updated');
    expect(logs[1].actionLabel, 'AI recommendation generated');
    expect(logs[0].performedBy, 'GSO Administrator');
    expect(logs[1].performedBy, 'admin');
  });

  testWidgets('entries grouped by day, filtered by module and search', (tester) async {
    await pump(tester);
    expect(find.text('3 entries'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Mar 4, 2026'), findsOneWidget);
    expect(find.text('Maintenance updated'), findsOneWidget);

    await tester.tap(find.text('Assets (2)'));
    await tester.pumpAndSettle();
    expect(find.text('Maintenance updated'), findsNothing);
    expect(find.text('Asset transferred'), findsOneWidget);

    await tester.tap(find.text('All (3)'));
    await tester.enterText(find.byType(TextField), 'mto');
    await tester.pump(const Duration(milliseconds: 400)); // the search box waits 350 ms after typing
    await tester.pumpAndSettle();
    expect(find.text('Asset transferred'), findsOneWidget);
    expect(find.text('AI recommendation generated'), findsNothing);

    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('No entries match your search.'), findsOneWidget);
  });

  testWidgets('tapping an entry shows all of it', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Maintenance updated'));
    await tester.pumpAndSettle();
    expect(find.text('GSO Administrator (admin)'), findsOneWidget);
    expect(find.text('asset #7'), findsOneWidget);
  });

  testWidgets('no overflow on a small phone at large text, archive sheet opens', (tester) async {
    await pump(tester, textScale: 1.3);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Archive'));
    await tester.pumpAndSettle();
    expect(find.text('12 archived entries, Mar 1, 2024 – Jan 10, 2025.'), findsOneWidget);
    expect(find.text('Export as CSV'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
