// The Property Return Slip (LGU Form No. 12) and the PAR made when an asset changes end user,
// in the same layout as the web's (frontend utils/returnPapersPrint.js): long bond paper,
// portrait, the municipal seal on top, one item whose table runs down to the certification.
// Built in a background isolate - see printPdf.

import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../reports/utils/print_form.dart';
import '../model/return_papers_model.dart';

/// Who signs for the GSO (receives the return, issues the PAR). The web lets this be changed.
const papersOfficerName = 'REGIE B. AGNO';
const papersOfficerPosition = 'MGDH I (MGSO)';

const longBond = PdfPageFormat(8.5 * PdfPageFormat.inch, 13 * PdfPageFormat.inch,
    marginLeft: 14 * PdfPageFormat.mm, marginRight: 14 * PdfPageFormat.mm,
    marginTop: 12 * PdfPageFormat.mm, marginBottom: 12 * PdfPageFormat.mm);

Future<void> printReturnSlip(ReturnSlipModel slip) async {
  final seal = (await rootBundle.load('assets/images/images.png')).buffer.asUint8List();
  await printPdf('Property Return Slip ${slip.slipNumber}', (fonts) => returnSlipPdf(slip, seal, fonts), format: longBond);
}

Future<void> printPar(ParIssueModel par) async {
  final seal = (await rootBundle.load('assets/images/images.png')).buffer.asUint8List();
  await printPdf('PAR ${par.parNumber}', (fonts) => parIssuePdf(par, seal, fonts), format: longBond);
}

// ── shared pieces ────────────────────────────────────────────────────────────

const _line = pw.BorderSide(width: 1);
const _outer = pw.BorderSide(width: 1.4);
const _months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September',
    'October', 'November', 'December'];

String _shortDate(String? d) {
  if (d == null || d.length < 10) return '';
  return '${d.substring(5, 7)}/${d.substring(8, 10)}/${d.substring(0, 4)}';
}

String _money(double? v) {
  if (v == null) return '';
  final parts = v.toStringAsFixed(2).split('.');
  final whole = parts[0].replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
  return '$whole.${parts[1]}';
}

String _ordinal(int n) {
  if (n % 100 >= 11 && n % 100 <= 13) return '${n}th';
  return '$n${switch (n % 10) { 1 => 'st', 2 => 'nd', 3 => 'rd', _ => 'th' }}';
}

pw.Document _doc(String title, PdfFonts fonts) => pw.Document(
      title: title,
      theme: pw.ThemeData.withFont(
        base: pw.Font.ttf(fonts.sans),
        bold: pw.Font.ttf(fonts.sansBold),
        fontFallback: [pw.Font.ttf(fonts.regular)],
      ),
    );

pw.Widget _head(Uint8List seal, String title, {String? formNo}) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        if (formNo != null) pw.Text(formNo, style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold)),
        pw.Center(child: pw.Image(pw.MemoryImage(seal), width: 52, height: 52)),
        pw.SizedBox(height: 5),
        pw.Center(child: pw.Text('Republic of the Philippines', style: const pw.TextStyle(fontSize: 10))),
        pw.Center(child: pw.Text('MUNICIPALITY OF SAN JOSE', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold))),
        pw.SizedBox(height: 10),
        pw.Center(child: pw.Text(title, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold))),
        pw.SizedBox(height: 12),
      ],
    );

pw.Widget _labelled(String label, String value) => pw.RichText(
      text: pw.TextSpan(style: const pw.TextStyle(fontSize: 9.5), children: [
        pw.TextSpan(text: label),
        pw.TextSpan(text: value, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
      ]),
    );

/// Description cell: the item in bold, then its specifications line by line.
pw.Widget _describe(PaperAsset a) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Text(a.description ?? '', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
      if (a.specifications != null && a.specifications!.trim().isNotEmpty) ...[
        pw.SizedBox(height: 3),
        pw.Text(a.specifications!.trim(), style: const pw.TextStyle(fontSize: 9, lineSpacing: 1.5)),
      ],
    ]);

/// The item table: a ruled header and one row that runs down to fill the page.
pw.Widget _itemsTable(List<(String, double)> columns, List<pw.Widget> cells) {
  pw.Widget column(int i, pw.Widget child, {required bool head}) => pw.Expanded(
        flex: (columns[i].$2 * 10).round(),
        child: pw.Container(
          padding: head ? const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 4) : const pw.EdgeInsets.all(4),
          alignment: head ? pw.Alignment.center : pw.Alignment.topLeft,
          decoration: pw.BoxDecoration(border: pw.Border(left: i == 0 ? pw.BorderSide.none : _line)),
          child: child,
        ),
      );
  return pw.Expanded(
    child: pw.Container(
      decoration: const pw.BoxDecoration(border: pw.Border(left: _outer, right: _outer, top: _outer, bottom: _outer)),
      child: pw.Column(children: [
        // a fixed height: a stretched row needs a bounded one, and two-line labels fit in it
        pw.Container(
          height: 30,
          decoration: const pw.BoxDecoration(border: pw.Border(bottom: _line)),
          child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
            for (var i = 0; i < columns.length; i++)
              column(i, pw.Text(columns[i].$1, textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold)), head: true),
          ]),
        ),
        pw.Expanded(
          child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
            for (var i = 0; i < columns.length; i++) column(i, cells[i], head: false),
          ]),
        ),
      ]),
    ),
  );
}

pw.Widget _c(String text, {pw.TextAlign align = pw.TextAlign.center}) =>
    pw.SizedBox(width: double.infinity, child: pw.Text(text, textAlign: align, style: const pw.TextStyle(fontSize: 9)));

/// Numbers stay on one line each, shrunk to fit their column rather than broken mid-number.
pw.Widget _fit(List<String> lines, {bool right = false}) => pw.Column(
      crossAxisAlignment: right ? pw.CrossAxisAlignment.end : pw.CrossAxisAlignment.center,
      children: [
        for (final l in lines)
          l.isEmpty
              ? pw.SizedBox(height: 8)
              : pw.FittedBox(
                  fit: pw.BoxFit.scaleDown,
                  alignment: right ? pw.Alignment.centerRight : pw.Alignment.center,
                  child: pw.Text(l, style: const pw.TextStyle(fontSize: 9))),
      ],
    );

pw.Widget _signature(String name, List<String> captions) => pw.Padding(
      padding: const pw.EdgeInsets.only(top: 26),
      child: pw.Column(children: [
        pw.Container(
          width: 170,
          padding: const pw.EdgeInsets.only(top: 2),
          decoration: const pw.BoxDecoration(border: pw.Border(top: _line)),
          child: pw.Text(name.toUpperCase(), textAlign: pw.TextAlign.center,
              style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold)),
        ),
        for (final c in captions)
          c.isEmpty ? pw.SizedBox(height: 8) : pw.Text(c, textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 8.5)),
      ]),
    );

pw.Widget _twoBoxes(pw.Widget left, pw.Widget right, {String? heading}) => pw.Container(
      decoration: const pw.BoxDecoration(border: pw.Border(left: _outer, right: _outer, bottom: _outer)),
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
        if (heading != null)
          pw.Container(
            padding: const pw.EdgeInsets.all(5),
            decoration: const pw.BoxDecoration(border: pw.Border(bottom: _line)),
            child: pw.Text(heading, textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold)),
          ),
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Expanded(child: pw.Padding(padding: const pw.EdgeInsets.fromLTRB(9, 8, 9, 12), child: left)),
          pw.Container(width: 1, height: 150, color: PdfColors.black),
          pw.Expanded(child: pw.Padding(padding: const pw.EdgeInsets.fromLTRB(9, 8, 9, 12), child: right)),
        ]),
      ]),
    );

// ── Property Return Slip ─────────────────────────────────────────────────────

Future<Uint8List> returnSlipPdf(ReturnSlipModel s, Uint8List seal, PdfFonts fonts) async {
  final doc = _doc('Property Return Slip ${s.slipNumber}', fonts);
  final date = DateTime.tryParse(s.returnDate) ?? DateTime.now();
  final day = _ordinal(date.day), month = _months[date.month - 1], year = date.year;
  final purposes = [('DISPOSAL', 'Disposal'), ('REPAIR', 'Repair'), ('RETURNED_TO_STOCK', 'Returned to Stock'), ('UNSERVICEABLE', 'Unserviceable')]
      .map((p) => '( ${s.purpose == p.$1 ? 'X' : '  '} ) ${p.$2}')
      .join('      ');
  const body = pw.TextStyle(fontSize: 9.5, lineSpacing: 2);

  doc.addPage(pw.Page(
    pageFormat: longBond,
    build: (ctx) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
      _head(seal, 'PROPERTY RETURN SLIP', formNo: 'LGU FORM NO. 12'),
      pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        pw.Expanded(child: _labelled('NAME OF OFFICE: ', (s.officeName ?? '').toUpperCase())),
        _labelled('No. ', s.slipNumber),
      ]),
      pw.SizedBox(height: 4),
      pw.Text('PURPOSE  :  $purposes', style: const pw.TextStyle(fontSize: 9.5)),
      pw.SizedBox(height: 4),
      _itemsTable(
        const [('QTY', 5), ('UNIT', 6), ('DESCRIPTION', 24), ('PROPERTY NUMBER', 16), ('DATE ACQUIRED', 11),
            ('NAME OF END-USER', 12), ('UNIT VALUE', 13.5), ('TOTAL VALUE', 12.5)],
        [
          _c('1'),
          _c('Unit'),
          _describe(s),
          _fit([s.propertyNumber, if (s.parNumber != null) ...['', 'PAR No.', s.parNumber!]]),
          _c(_shortDate(s.acquisitionDate)),
          _c(s.returnedByName.toUpperCase()),
          _fit([if (s.unitValue != null) 'PHP ${_money(s.unitValue)}'], right: true),
          _fit([_money(s.unitValue)], right: true),
        ],
      ),
      _twoBoxes(
        pw.Column(children: [
          pw.Text('I HEREBY CERTIFY that I have this $day day of $month, $year returned to $papersOfficerName MGSO the items / articles described above.', style: body),
          _signature(s.returnedByName, [s.returnedByPosition ?? '']),
        ]),
        pw.Column(children: [
          pw.Text('I HEREBY CERTIFY that I have this $day day of $month, $year RECEIVED from ${s.returnedByName} the items / articles described above.', style: body),
          _signature(papersOfficerName, [papersOfficerPosition]),
        ]),
        heading: 'CERTIFICATION',
      ),
    ]),
  ));
  return doc.save();
}

// ── PAR ──────────────────────────────────────────────────────────────────────

Future<Uint8List> parIssuePdf(ParIssueModel p, Uint8List seal, PdfFonts fonts) async {
  final doc = _doc('PAR ${p.parNumber}', fonts);
  final issued = _shortDate(p.issueDate);
  final position = [p.personnelPosition, p.officeName].whereType<String>().where((s) => s.isNotEmpty).join(', ');

  pw.Widget signer(String who, String name, String caption, String positionText) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Text(who, style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold)),
          _signature(name, [caption, '', positionText, 'Position / Office', '', issued, 'Date']),
        ],
      );

  doc.addPage(pw.Page(
    pageFormat: longBond,
    build: (ctx) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
      _head(seal, 'PROPERTY ACKNOWLEDGEMENT RECEIPT'),
      pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        _labelled('Entity Name: ', 'MUNICIPALITY OF SAN JOSE, BATANGAS'),
        _labelled('PAR No.: ', p.parNumber),
      ]),
      pw.SizedBox(height: 4),
      pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        pw.Expanded(child: _labelled('Office: ', (p.officeName ?? '').toUpperCase())),
        pw.Text('Fund Cluster: ________________', style: const pw.TextStyle(fontSize: 9.5)),
      ]),
      pw.SizedBox(height: 4),
      _itemsTable(
        const [('Quantity', 8), ('Unit', 8), ('Description', 38), ('Property Number', 18), ('Date Acquired', 13), ('Amount', 15)],
        [
          _c('1'),
          _c('Unit'),
          _describe(p),
          _fit([p.propertyNumber]),
          _c(_shortDate(p.acquisitionDate)),
          _fit([if (p.unitValue != null) 'PHP ${_money(p.unitValue)}'], right: true),
        ],
      ),
      _twoBoxes(
        signer('Received by:', p.personnelName ?? '', 'Signature over Printed Name of End User', position),
        signer('Issued by:', papersOfficerName, 'Signature over Printed Name of Supply and/or Property Custodian',
            papersOfficerPosition),
      ),
    ]),
  ));
  return doc.save();
}
