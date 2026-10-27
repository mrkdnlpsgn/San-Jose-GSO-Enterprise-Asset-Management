// The PAR and Property Card printouts, in the same layout as the web's (Reports page PAR form,
// utils/propertyCardExport.js). Built in a background isolate - see printPdf.

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'print_form.dart';

// ── PAR ──────────────────────────────────────────────────────────────────────

class ParLine {
  final String qty, propertyNumber, date, amount;
  /// The Description cell's lines: item, Brand/Model, S/N, then the specifications.
  final List<String> description;
  const ParLine(this.qty, this.description, this.propertyNumber, this.date, this.amount);
}

class ParForm {
  final String par, office, entity, fund, receivedBy, total;
  final List<ParLine> lines;
  const ParForm({
    required this.par,
    required this.office,
    required this.entity,
    required this.fund,
    required this.receivedBy,
    required this.total,
    required this.lines,
  });
}

// Inter has no ₱, so the amounts fall back to Tinos for that one sign.
pw.ThemeData _sansTheme(PdfFonts fonts) => pw.ThemeData.withFont(
      base: pw.Font.ttf(fonts.sans),
      bold: pw.Font.ttf(fonts.sansBold),
      italic: pw.Font.ttf(fonts.sans),
      fontFallback: [pw.Font.ttf(fonts.regular)],
    );

const _black = pw.BorderSide(width: 0.75);
const _grey = pw.BorderSide(width: 0.75, color: PdfColor.fromInt(0xFFBBBBBB));

Future<Uint8List> buildParPdf(String title, List<ParForm> forms, PdfFonts fonts) async {
  final serifBold = pw.Font.ttf(fonts.bold);
  final doc = pw.Document(
    title: title,
    theme: _sansTheme(fonts),
  );
  final serifHead = pw.TextStyle(font: serifBold, fontSize: 10.5);
  const widths = {
    0: pw.FlexColumnWidth(8), 1: pw.FlexColumnWidth(8), 2: pw.FlexColumnWidth(44),
    3: pw.FlexColumnWidth(17), 4: pw.FlexColumnWidth(11), 5: pw.FlexColumnWidth(12),
  };

  pw.Widget cell(String text, {pw.TextAlign align = pw.TextAlign.left, bool first = true, bool italic = false}) => pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2.25),
        decoration: pw.BoxDecoration(border: pw.Border(top: first ? _black : _grey)),
        child: pw.Text(text.isEmpty ? ' ' : text,
            textAlign: align, style: pw.TextStyle(fontSize: 9, fontStyle: italic ? pw.FontStyle.italic : null)),
      );

  for (final f in forms) {
    final rows = <pw.TableRow>[
      pw.TableRow(children: [
        for (final h in ['Quantity', 'Unit', 'Description', 'Property Number', 'Date Acquired', 'Amount'])
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 1, vertical: 6),
            alignment: pw.Alignment.center,
            child: pw.Text(h, textAlign: pw.TextAlign.center, style: serifHead),
          ),
      ]),
    ];
    for (final l in f.lines) {
      for (var i = 0; i < l.description.length; i++) {
        final line = l.description[i];
        final specHead = line == 'Technical Specifications:';
        rows.add(pw.TableRow(children: i == 0
            ? [
                cell(l.qty, align: pw.TextAlign.center),
                cell('Unit', align: pw.TextAlign.center),
                cell(line, italic: specHead),
                cell(l.propertyNumber, align: pw.TextAlign.center),
                cell(l.date, align: pw.TextAlign.center),
                cell(l.amount, align: pw.TextAlign.right),
              ]
            : [cell('', first: false), cell('', first: false), cell(line, first: false, italic: specHead),
                cell('', first: false), cell('', first: false), cell('', first: false)]));
      }
    }

    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(21),
      build: (ctx) => [
        pw.Center(child: pw.Text('PROPERTY ACKNOWLEDGMENT RECEIPT', style: pw.TextStyle(font: serifBold, fontSize: 15))),
        pw.Center(child: pw.Text('(${f.office.toUpperCase()})', style: pw.TextStyle(font: serifBold, fontSize: 12))),
        pw.SizedBox(height: 13),
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.end, mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            for (final (k, v) in [('Entity Name', f.entity), ('Fund Cluster', f.fund)])
              pw.Row(children: [
                pw.SizedBox(width: 82, child: pw.Text(k, style: serifHead)),
                pw.Text(': $v', style: serifHead),
              ]),
          ]),
          pw.Text('PAR No. : ${f.par}', style: serifHead),
        ]),
        pw.SizedBox(height: 6),
        pw.Table(
          columnWidths: widths,
          border: const pw.TableBorder(left: _black, right: _black, top: _black, bottom: _black, verticalInside: _black),
          children: rows,
        ),
        pw.Table(
          columnWidths: const {0: pw.FlexColumnWidth(88), 1: pw.FlexColumnWidth(12)},
          border: pw.TableBorder.all(width: 0.75),
          children: [
            pw.TableRow(children: [
              pw.Padding(padding: const pw.EdgeInsets.all(4.5),
                  child: pw.Text('TOTAL', textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold))),
              pw.Padding(padding: const pw.EdgeInsets.all(4.5),
                  child: pw.FittedBox(
                      fit: pw.BoxFit.scaleDown,
                      alignment: pw.Alignment.centerRight,
                      child: pw.Text(f.total, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)))),
            ]),
          ],
        ),
        pw.Container(
          decoration: const pw.BoxDecoration(border: pw.Border(left: _black, right: _black, bottom: _black)),
          child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Expanded(child: _parSigner('Received by:', f.receivedBy, 'Signature over Printed Name of End User')),
            pw.Container(width: 0.75, height: 150, color: PdfColors.black),
            pw.Expanded(child: _parSigner('Issued by:', '', 'Signature over Printed Name of Supply and/or Property Custodian')),
          ]),
        ),
      ],
    ));
  }
  return doc.save();
}

pw.Widget _parSigner(String who, String name, String caption) {
  const cap = pw.TextStyle(fontSize: 7.5);
  pw.Widget line() => pw.Container(
      margin: const pw.EdgeInsets.only(top: 13.5),
      decoration: const pw.BoxDecoration(border: pw.Border(bottom: _black)),
      height: 1);
  return pw.Padding(
    padding: const pw.EdgeInsets.fromLTRB(10.5, 7.5, 10.5, 10.5),
    child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
      pw.Text(who, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
      pw.Container(
        margin: const pw.EdgeInsets.only(top: 22.5),
        constraints: const pw.BoxConstraints(minHeight: 13.5),
        decoration: const pw.BoxDecoration(border: pw.Border(bottom: _black)),
        child: pw.Text(name.toUpperCase(), textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
      ),
      pw.Padding(padding: const pw.EdgeInsets.only(bottom: 9), child: pw.Text(caption, textAlign: pw.TextAlign.center, style: cap)),
      line(),
      pw.Padding(padding: const pw.EdgeInsets.only(bottom: 9), child: pw.Text('Position/Office', textAlign: pw.TextAlign.center, style: cap)),
      line(),
      pw.Text('Date', textAlign: pw.TextAlign.center, style: cap),
    ]),
  );
}

// ── Property Card ────────────────────────────────────────────────────────────

/// The paper form has room for this many lines; shorter cards are padded with blank rows.
const propertyCardFormRows = 14;

class CardForm {
  final String category;
  /// Date, Reference Property #, Description (lines), Receipt Qty, Transfer, Office, Balance Qty
  final List<List<String>> entries;
  const CardForm(this.category, this.entries);
}

Future<Uint8List> buildPropertyCardPdf(String title, String entity, List<CardForm> cards, PdfFonts fonts) async {
  final doc = pw.Document(
    title: title,
    theme: _sansTheme(fonts),
  );
  const flex = [11.0, 15.0, 26.0, 8.0, 15.0, 17.0, 8.0];
  const cols = ['Date', 'Reference Property #', 'Description', 'Receipt Qty', 'Transfer', 'Office', 'Balance Qty'];
  const all = pw.Border(left: _black, right: _black, top: _black, bottom: _black);
  final bold = pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9);

  pw.Widget box(pw.Widget child, {pw.Alignment align = pw.Alignment.center, double pad = 4.5}) => pw.Container(
      width: double.infinity, alignment: align, padding: pw.EdgeInsets.all(pad), decoration: const pw.BoxDecoration(border: all), child: child);

  for (final card in cards) {
    final rows = [
      ...card.entries,
      for (var i = card.entries.length; i < propertyCardFormRows; i++) List.filled(7, ''),
    ];
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(21),
      build: (ctx) => [
        box(pw.Text('PROPERTY CARD', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13.5, letterSpacing: 0.5)), pad: 7.5),
        box(pw.Column(children: [
          pw.Text(entity, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
          pw.Text('LGU', style: const pw.TextStyle(fontSize: 10)),
        ])),
        pw.Row(children: [
          pw.Expanded(
            flex: 60,
            child: box(
                pw.RichText(text: pw.TextSpan(style: bold, children: [
                  const pw.TextSpan(text: 'Plant, Property and Equipment: '),
                  pw.TextSpan(text: card.category, style: pw.TextStyle(fontWeight: pw.FontWeight.normal, decoration: pw.TextDecoration.underline)),
                ])),
                align: pw.Alignment.centerLeft),
          ),
          pw.Expanded(flex: 40, child: box(pw.Text('Property Classification:', style: bold), align: pw.Alignment.centerLeft)),
        ]),
        pw.Table(
          columnWidths: {for (var i = 0; i < flex.length; i++) i: pw.FlexColumnWidth(flex[i])},
          border: pw.TableBorder.all(width: 0.75),
          children: [
            pw.TableRow(verticalAlignment: pw.TableCellVerticalAlignment.middle, children: [
              for (final c in cols)
                pw.Padding(padding: const pw.EdgeInsets.all(4.5), child: pw.Text(c, textAlign: pw.TextAlign.center, style: bold)),
            ]),
            for (final r in rows)
              pw.TableRow(children: [
                for (var i = 0; i < 7; i++)
                  pw.Container(
                    constraints: const pw.BoxConstraints(minHeight: 19.5),
                    padding: const pw.EdgeInsets.symmetric(horizontal: 4.5, vertical: 3.75),
                    child: pw.Text(r[i], textAlign: i == 2 ? pw.TextAlign.left : pw.TextAlign.center, style: const pw.TextStyle(fontSize: 9)),
                  ),
              ]),
          ],
        ),
      ],
    ));
  }
  return doc.save();
}
