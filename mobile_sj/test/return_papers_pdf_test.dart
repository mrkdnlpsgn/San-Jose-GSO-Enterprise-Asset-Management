import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:san_jose_eam_mobile/features/assets/model/return_papers_model.dart';
import 'package:san_jose_eam_mobile/features/assets/utils/return_papers_pdf.dart';
import 'package:san_jose_eam_mobile/features/reports/utils/print_form.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final papers = ReturnPapersModel.fromJson({
    'returnSlips': [
      {'id': 1, 'slipNumber': 'PRS-2026-0001', 'transferId': 7, 'purpose': 'RETURNED_TO_STOCK', 'officeName': 'Office of the Municipal Treasurer',
       'returnedByName': 'Rabanne B. Ditan', 'returnedByPosition': 'MGDH I (Municipal Treasurer)', 'returnDate': '2026-10-07',
       'propertyNumber': '2023-06-010-958-1091', 'parNumber': '2023-05:SDB1549', 'description': 'Toyota Hi-Ace GL Grandia',
       'specifications': 'Make: Toyota\nBody Type: Van\nPlate No.: SDB-1549', 'unitValue': 2479000, 'acquisitionDate': '2023-05-23',
       'createdAt': '2026-10-07T01:00:00Z'},
    ],
    'pars': [
      {'id': 2, 'parNumber': '2023-05:SDB1549-2', 'transferId': 7, 'personnelName': 'Juan Dela Cruz', 'personnelPosition': 'Driver',
       'officeName': 'General Services Office', 'issueDate': '2026-10-07', 'propertyNumber': '2023-06-010-958-1091',
       'description': 'Toyota Hi-Ace GL Grandia', 'specifications': 'Make: Toyota', 'unitValue': 2479000,
       'acquisitionDate': '2023-05-23', 'original': false, 'createdAt': '2026-10-07T01:00:00Z'},
      {'id': 1, 'parNumber': '2023-05:SDB1549', 'transferId': null, 'personnelName': 'Rabanne B. Ditan', 'issueDate': '2023-05-23',
       'propertyNumber': '2023-06-010-958-1091', 'original': true, 'createdAt': '2026-10-07T01:00:00Z'},
    ],
  });

  test('groups a transfer\'s slip and PAR into one row, original PAR last', () {
    final rows = papers.rows;
    expect(rows.length, 2);
    expect(rows[0].slip?.slipNumber, 'PRS-2026-0001');
    expect(rows[0].par?.parNumber, '2023-05:SDB1549-2');
    expect(rows[1].isOriginal, isTrue);
  });

  test('builds both PDFs', () async {
    final fonts = await loadPdfFonts();
    final seal = (await rootBundle.load('assets/images/images.png')).buffer.asUint8List();
    final slip = await returnSlipPdf(papers.returnSlips.first, seal, fonts);
    final par = await parIssuePdf(papers.pars.first, seal, fonts);
    expect(slip.length, greaterThan(1000));
    expect(par.length, greaterThan(1000));
    final out = Platform.environment['PAPERS_OUT'];
    if (out != null) {
      File('$out/m_slip.pdf').writeAsBytesSync(slip);
      File('$out/m_par.pdf').writeAsBytesSync(par);
    }
  });
}
