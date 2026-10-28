import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:san_jose_eam_mobile/features/reports/utils/maintenance_card.dart';
import 'package:san_jose_eam_mobile/features/reports/utils/print_form.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final records = <Map<String, dynamic>>[
    {'id': 2, 'asset': {'id': 7, 'propertyNumber': '2021-05-090-726-1101', 'description': 'Toyota Hilux-Pick Up 4X4 Conquest'},
     'maintenanceDate': '2023-10-18', 'actionsTaken': 'Replacement of Various Parts (Automatic Motors)', 'cost': 14515, 'approvalStatus': 'APPROVED',
     'items': [
       {'kind': 'PART', 'particular': 'Flushing Oil', 'unit': 'can', 'quantity': 1, 'unitCost': 348, 'totalCost': 348},
       {'kind': 'PART', 'particular': 'Fully Synthetic Engine Oil (5w40)', 'unit': 'liters', 'quantity': 7, 'unitCost': 548, 'totalCost': 3836},
       {'kind': 'LABOR', 'particular': 'Change Oil Labor', 'totalCost': 498},
     ]},
    {'id': 1, 'asset': {'id': 7, 'propertyNumber': '2021-05-090-726-1101', 'description': 'Toyota Hilux-Pick Up 4X4 Conquest'},
     'maintenanceDate': '2022-02-17', 'actionsTaken': '5,000 KM Periodic Maintenance Service - Toyota Lipa', 'cost': 9177.56, 'approvalStatus': 'APPROVED', 'items': []},
    {'id': 3, 'asset': {'id': 7}, 'maintenanceDate': '2024-01-01', 'actionsTaken': 'Waiting', 'cost': 1, 'approvalStatus': 'PENDING_APPROVAL'},
    // the placeholder opened when an asset is marked repairable: nothing done yet
    {'id': 4, 'asset': {'id': 7}, 'maintenanceDate': '2024-02-01', 'actionsTaken': 'Pending review and assignment', 'cost': null,
     'status': 'ONGOING', 'approvalStatus': 'APPROVED', 'items': []},
    // an asset whose only record is such a placeholder has no card
    {'id': 5, 'asset': {'id': 8}, 'maintenanceDate': '2024-02-01', 'actionsTaken': 'Pending review and assignment', 'cost': null,
     'status': 'ONGOING', 'approvalStatus': 'APPROVED'},
  ];
  final assets = <Map<String, dynamic>>[
    {'id': 7, 'unitValue': 2498500, 'office': {'officeName': "Mayor's Office"}},
  ];

  test('one card per asset, approved records only, in date order', () {
    final cards = maintenanceCardsOf(records, assets);
    expect(cards.length, 1);
    expect(cards[0]['repairs'], 2);
    expect(cards[0]['department'], "Mayor's Office");
    final lines = maintenanceCardLines(cards[0]['records'] as List);
    expect(lines.map((l) => l['kind']).toList(), ['repair', 'repair', 'part', 'part', 'laborHead', 'labor']);
    expect(lines[0]['date'], 'February 17, 2022');
    expect(lines[0]['cost'], '9,177.56');
    expect(lines[3]['total'], '3,836.00');
  });

  test('builds the card PDF', () async {
    final cards = maintenanceCardsOf(records, assets);
    final bytes = await buildMaintenanceCardPdf('t', [
      {'propertyNumber': cards[0]['propertyNumber'], 'description': cards[0]['description'], 'unitValue': '2,498,500.00',
       'department': cards[0]['department'], 'lines': maintenanceCardLines(cards[0]['records'] as List)},
    ], await loadPdfFonts());
    expect(bytes.length, greaterThan(1000));
    final out = Platform.environment['PAPERS_OUT'];
    if (out != null) File('$out/m_card.pdf').writeAsBytesSync(bytes);
  });
}
