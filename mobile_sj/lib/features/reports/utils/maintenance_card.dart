// The GSO's Repair and Maintenance Card (Machineries & Equipment), one per asset - the same as the
// web's (frontend utils/maintenanceCardPrint.js): every approved maintenance record in date order,
// each with its parts (unit, quantity, unit cost, total) and its labor under "Labor:", and the
// record's cost of repair on its own line. Landscape long bond paper, one card per page (or more
// for a long card); Excel gets one sheet per card.

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../model/report_definition.dart';
import 'export_excel.dart';
import 'print_form.dart';
import 'report_format.dart';

const maintenanceCardTitle = 'REPAIR AND MAINTENANCE CARD (MACHINERIES & EQUIPMENT)';

const _months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September',
    'October', 'November', 'December'];

String _repairDate(Object? d) {
  final k = str(d);
  if (k.length < 10) return '';
  return '${_months[int.parse(k.substring(5, 7)) - 1]} ${k.substring(8, 10)}, ${k.substring(0, 4)}';
}

String _money(Object? v) {
  if (v == null || v == '') return '';
  final parts = toNum(v).toDouble().toStringAsFixed(2).split('.');
  return '${parts[0].replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',')}.${parts[1]}';
}

String _qty(Object? v) {
  if (v == null) return '';
  final n = toNum(v);
  return n == n.roundToDouble() ? n.toInt().toString() : n.toString();
}

bool _counted(Map r) => r['approvalStatus'] == null || r['approvalStatus'] == 'APPROVED';
int _byDate(Map a, Map b) {
  final c = str(a['maintenanceDate']).compareTo(str(b['maintenanceDate']));
  return c != 0 ? c : toNum(a['id']).compareTo(toNum(b['id']));
}

/// One card per asset that has approved maintenance; `assets` fills in the acquisition cost and
/// department, which maintenance records don't carry. Newest repair first.
List<ReportRow> maintenanceCardsOf(List<ReportRow> records, List<ReportRow> assets) {
  final assetById = {for (final a in assets) str(a['id']): a};
  final byAsset = <String, List<ReportRow>>{};
  for (final r in records) {
    final id = str(at(r, 'asset.id'));
    if (!_counted(r) || id.isEmpty) continue;
    byAsset.putIfAbsent(id, () => []).add(r);
  }
  final cards = [
    for (final e in byAsset.entries)
      () {
        final recs = [...e.value]..sort(_byDate);
        final asset = Map<String, dynamic>.from({...(recs.first['asset'] as Map? ?? const {}), ...?assetById[e.key]});
        return <String, dynamic>{
          'assetId': e.key,
          'propertyNumber': str(asset['propertyNumber']),
          'description': str(asset['description']),
          'unitValue': asset['unitValue'],
          'department': str(at(asset, 'office.officeName')),
          'records': recs,
          'repairs': recs.length,
          'totalCost': recs.fold<num>(0, (t, r) => t + toNum(r['cost'])),
          'lastRepair': str(recs.last['maintenanceDate']),
        };
      }(),
  ]..sort((a, b) => str(b['lastRepair']).compareTo(str(a['lastRepair'])));
  return cards;
}

/// A card's lines, top to bottom: each repair, then its parts, "Labor:" and the labor. Every line
/// has the card's seven columns (blank where the paper leaves them blank).
List<Map<String, dynamic>> maintenanceCardLines(List records) {
  final sorted = [for (final r in records) r as Map]..retainWhere(_counted)..sort(_byDate);
  Map<String, dynamic> line(String kind, {String date = '', String particular = '', String unit = '',
          String quantity = '', String unitCost = '', String total = '', String cost = ''}) =>
      {'kind': kind, 'date': date, 'particular': particular, 'unit': unit, 'quantity': quantity,
        'unitCost': unitCost, 'total': total, 'cost': cost};
  return [
    for (final r in sorted) ...() {
      final items = [for (final i in (r['items'] as List? ?? const [])) i as Map];
      final parts = items.where((i) => i['kind'] != 'LABOR');
      final labor = items.where((i) => i['kind'] == 'LABOR').toList();
      return [
        line('repair', date: _repairDate(r['maintenanceDate']),
            particular: str(r['actionsTaken']).isNotEmpty ? str(r['actionsTaken']) : str(r['findings']),
            cost: _money(r['cost'])),
        for (final p in parts)
          line('part', particular: str(p['particular']), unit: str(p['unit']), quantity: _qty(p['quantity']),
              unitCost: _money(p['unitCost']), total: _money(p['totalCost'])),
        if (labor.isNotEmpty) line('laborHead', particular: 'Labor:'),
        for (final l in labor) line('labor', particular: str(l['particular']), total: _money(l['totalCost'])),
      ];
    }(),
  ];
}

const _lineKeys = ['date', 'particular', 'unit', 'quantity', 'unitCost', 'total', 'cost'];
const _headers = ['DATE OF REPAIR', 'PARTICULAR', 'UNIT', 'QUANTITY', 'UNIT COST', 'TOTAL COST', 'COST OF REPAIR'];
const _flex = [12.0, 36.0, 8.0, 8.0, 9.0, 9.0, 18.0];

const landscapeLongBond = PdfPageFormat(13 * PdfPageFormat.inch, 8.5 * PdfPageFormat.inch,
    marginLeft: 12 * PdfPageFormat.mm, marginRight: 12 * PdfPageFormat.mm,
    marginTop: 10 * PdfPageFormat.mm, marginBottom: 10 * PdfPageFormat.mm);

Future<void> printMaintenanceCards(List<PickItem> cards) {
  final title = cards.length == 1
      ? 'Repair and Maintenance Card ${cards[0]['propertyNumber']}'
      : 'Repair and Maintenance Cards (${cards.length})';
  // plain maps cross into the PDF isolate
  final data = [
    for (final c in cards)
      {
        'propertyNumber': str(c['propertyNumber']),
        'description': str(c['description']),
        'unitValue': _money(c['unitValue']),
        'department': str(c['department']),
        'lines': maintenanceCardLines(c['records'] as List? ?? const []),
      },
  ];
  return printPdf(title, (fonts) => buildMaintenanceCardPdf(title, data, fonts), format: landscapeLongBond);
}

Future<Uint8List> buildMaintenanceCardPdf(String title, List<Map<String, dynamic>> cards, PdfFonts fonts) async {
  final doc = pw.Document(
    title: title,
    theme: pw.ThemeData.withFont(base: pw.Font.ttf(fonts.sans), bold: pw.Font.ttf(fonts.sansBold), italic: pw.Font.ttf(fonts.sans)),
  );
  const line = pw.BorderSide(width: 0.75);
  const cell = pw.TextStyle(fontSize: 9.5);
  final bold = pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold);
  final italic = pw.TextStyle(fontSize: 9.5, fontStyle: pw.FontStyle.italic);

  pw.Widget text(String t, {pw.TextAlign align = pw.TextAlign.left, pw.TextStyle? style, double indent = 0}) => pw.Padding(
        padding: pw.EdgeInsets.fromLTRB(5 + indent, 2.5, 5, 2.5),
        child: pw.Text(t, textAlign: align, style: style ?? cell),
      );

  for (final c in cards) {
    final lines = [for (final l in c['lines'] as List) l as Map];
    final rows = <pw.TableRow>[
      pw.TableRow(children: [
        for (final h in _headers)
          pw.Padding(padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 5),
              child: pw.Text(h, textAlign: pw.TextAlign.center, style: bold)),
      ]),
      for (final l in lines)
        l['kind'] == 'repair'
            ? pw.TableRow(children: [
                text(str(l['date']), align: pw.TextAlign.center),
                text(str(l['particular'])),
                pw.SizedBox(), pw.SizedBox(), pw.SizedBox(), pw.SizedBox(),
                text(str(l['cost']), align: pw.TextAlign.right),
              ])
            : pw.TableRow(children: [
                pw.SizedBox(),
                text(str(l['particular']), indent: 8,
                    style: l['kind'] == 'laborHead' ? italic : null),
                text(str(l['unit']), align: pw.TextAlign.center),
                text(str(l['quantity']), align: pw.TextAlign.center),
                text(str(l['unitCost']), align: pw.TextAlign.right),
                text(str(l['total']), align: pw.TextAlign.right),
                pw.SizedBox(),
              ]),
      // ruled blank lines for repairs written in by hand
      for (var i = 0; i < 5; i++) pw.TableRow(children: [for (var k = 0; k < 7; k++) pw.SizedBox(height: 16)]),
    ];

    doc.addPage(pw.MultiPage(
      pageFormat: landscapeLongBond,
      build: (ctx) => [
        pw.Container(
          padding: const pw.EdgeInsets.fromLTRB(9, 6, 9, 8),
          decoration: pw.BoxDecoration(border: pw.Border.all(width: 1.2)),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
            pw.Center(child: pw.Text(maintenanceCardTitle, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold))),
            pw.SizedBox(height: 6),
            pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
              _kv('TYPE OF MACHINE / EQUIPMENT : ', str(c['description'])),
              _kv('ACQUISITION COST: ', 'Php ${c['unitValue']}'),
            ]),
            pw.SizedBox(height: 3),
            pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
              _kv('PROPERTY NO.   ', str(c['propertyNumber'])),
              _kv('DEPARTMENT : ', str(c['department'])),
            ]),
          ]),
        ),
        pw.Table(
          columnWidths: {for (var i = 0; i < _flex.length; i++) i: pw.FlexColumnWidth(_flex[i])},
          border: const pw.TableBorder(left: line, right: line, bottom: line, horizontalInside: line, verticalInside: line),
          children: rows,
        ),
      ],
    ));
  }
  return doc.save();
}

pw.Widget _kv(String k, String v) => pw.RichText(
      text: pw.TextSpan(style: const pw.TextStyle(fontSize: 10), children: [
        pw.TextSpan(text: k),
        pw.TextSpan(text: v, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
      ]),
    );

/// One sheet per card, laid out like the paper: title, the four header details, then the table.
Future<void> exportMaintenanceCardsExcel(List<PickItem> cards) {
  final sheets = [
    for (final c in cards)
      SheetSpec(str(c['propertyNumber']), [
        [maintenanceCardTitle],
        ['TYPE OF MACHINE / EQUIPMENT : ${str(c['description'])}', '', '', '', '', 'ACQUISITION COST: Php ${_money(c['unitValue'])}'],
        ['PROPERTY NO. ${str(c['propertyNumber'])}', '', '', '', '', 'DEPARTMENT : ${str(c['department'])}'],
        _headers,
        for (final l in maintenanceCardLines(c['records'] as List? ?? const [])) [for (final k in _lineKeys) l[k]],
      ], widths: const [20, 48, 9, 10, 13, 13, 18], merges: const [
        [0, 0, 0, 6], [1, 0, 1, 4], [1, 5, 1, 6], [2, 0, 2, 4], [2, 5, 2, 6],
      ]),
  ];
  final file = cards.length == 1
      ? 'Repair_Maintenance_Card_${safeName(str(cards[0]['propertyNumber']))}'
      : 'Repair_Maintenance_Cards_${cards.length}';
  return shareWorkbook('${file}_${stampToday()}.xlsx', sheets);
}

/// The card's columns, for the preview under each picked asset.
final maintenanceCardHeaders = [
  for (var i = 0; i < _lineKeys.length; i++)
    ReportColumn(_headers[i][0] + _headers[i].substring(1).toLowerCase(),
        display: (l) => str(l[_lineKeys[i]]), raw: (l) => l[_lineKeys[i]]),
];
