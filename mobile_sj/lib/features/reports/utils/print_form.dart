// The standard printed report format, the same as the web's (frontend utils/printForm.js), taken
// from the GSO's printed RPCPPE: legal landscape, a Times face (Tinos), a centred title block, a
// ruled table and the page number at the bottom right. Every page holds ROWS_PER_PAGE rows of
// equal height that fill the rest of the page, under the title block and table header; pages
// short of rows are padded with blank ones, except the last page of a form, whose table ends at
// its last row with the signatures right below it. When a page's rows can't hold their text, the
// table text is made smaller on every page alike, so no table runs off its page.
//
// The PDF is built in a background isolate: a long report used to be built on the UI thread,
// which froze the app for half a minute and then failed.

import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

const rowsPerPage = 8;

/// The report fonts: Tinos (metric-compatible with Times New Roman) for the forms, and Inter
/// (the app's own face) where the web form uses a sans-serif body. Both have ₱.
class PdfFonts {
  final ByteData regular, bold, italic, sans, sansBold;
  const PdfFonts(this.regular, this.bold, this.italic, this.sans, this.sansBold);
}

Future<PdfFonts> loadPdfFonts() async => PdfFonts(
      await rootBundle.load('assets/fonts/Tinos-Regular.ttf'),
      await rootBundle.load('assets/fonts/Tinos-Bold.ttf'),
      await rootBundle.load('assets/fonts/Tinos-Italic.ttf'),
      await rootBundle.load('assets/fonts/Inter-400.ttf'),
      await rootBundle.load('assets/fonts/Inter-700.ttf'),
    );

/// Builds the PDF in a background isolate, then opens the system print dialog, set to the
/// form's paper (otherwise Android picks its default A4 portrait and shrinks the pages onto it).
Future<void> printPdf(String name, Future<Uint8List> Function(PdfFonts fonts) build, {PdfPageFormat? format}) async {
  final fonts = await loadPdfFonts();
  final bytes = await Isolate.run(() => build(fonts));
  await Printing.layoutPdf(name: name, format: format ?? standardFormat, onLayout: (_) async => bytes);
}

class FormColumn {
  final String label;
  /// Columns next to each other with the same group share a heading above their own labels.
  final String? group;
  final double width;
  /// l, c or r
  final String align;
  final bool italic;
  const FormColumn(this.label, {this.group, this.width = 1, this.align = 'l', this.italic = false});
}

/// A run of the accountability statement; bold runs are the officer and the date.
class TextRun {
  final String text;
  final bool bold;
  const TextRun(this.text, {this.bold = false});
}

/// One form: a type of PPE on the RPCPPE, or a whole report. It may run to several pages.
class StdForm {
  final String h1, h2;
  final List<String> lines;
  final String fund;
  final List<TextRun>? accountability;
  final List<FormColumn> columns;
  final List<List<String>> rows;
  const StdForm({
    required this.h1,
    required this.h2,
    required this.lines,
    required this.fund,
    this.accountability,
    required this.columns,
    required this.rows,
  });
}

class StdSigner {
  final String label, caption;
  const StdSigner(this.label, this.caption);
}

// ── layout ───────────────────────────────────────────────────────────────────

const _mm = PdfPageFormat.mm;
final standardFormat = PdfPageFormat.legal.landscape;
final _format = standardFormat;
const _mL = 12 * _mm, _mR = 12 * _mm, _mT = 12 * _mm, _mB = 14 * _mm;
const _padH = 4.0, _padV = 3.0;
const _outer = 1.5, _inner = 0.75;

class _Measure {
  final PdfFont regular, bold, italic;
  _Measure(PdfFonts f)
      : regular = PdfTtfFont(PdfDocument(), f.regular),
        bold = PdfTtfFont(PdfDocument(), f.bold),
        italic = PdfTtfFont(PdfDocument(), f.italic);

  double lineH(double size) => size * (regular.ascent - regular.descent);

  double width(PdfFont f, String s, double size) => f.stringMetrics(s).advanceWidth * size;

  /// Lines the text wraps to in [maxW].
  int lines(PdfFont f, String text, double size, double maxW) {
    if (maxW <= 0) return 1;
    var total = 0;
    for (final para in text.split('\n')) {
      var n = 1;
      var cur = 0.0;
      final space = width(f, ' ', size);
      for (final word in para.split(' ')) {
        if (word.isEmpty) continue;
        final w = width(f, word, size);
        if (cur == 0) {
          n += (w / maxW).ceil() - 1;
          cur = w > maxW ? w % maxW : w;
        } else if (cur + space + w <= maxW) {
          cur += space + w;
        } else {
          n += (w / maxW).ceil();
          cur = w > maxW ? w % maxW : w;
        }
      }
      total += n;
    }
    return math.max(total, 1);
  }
}

Future<Uint8List> buildStandardPdf(String title, List<StdForm> forms, List<StdSigner> signers, PdfFonts fonts) async {
  final m = _Measure(fonts);
  final theme = pw.ThemeData.withFont(
    base: pw.Font.ttf(fonts.regular),
    bold: pw.Font.ttf(fonts.bold),
    italic: pw.Font.ttf(fonts.italic),
  );
  final doc = pw.Document(title: title, theme: theme);
  final contentW = _format.width - _mL - _mR;
  final contentH = _format.height - _mT - _mB;
  final tableW = contentW - 2 * _outer;

  // signature block: 28 gap, label, 34 line, caption
  final sigCapW = signers.isEmpty ? 0.0 : (contentW - 32 * (signers.length - 1)) / signers.length;
  final sigCapLines = signers.isEmpty
      ? 0
      : signers.map((s) => m.lines(m.regular, s.caption, 9, sigCapW)).reduce(math.max);
  final sigH = signers.isEmpty ? 0.0 : 28 + m.lineH(10.5) + 34 + 3 + sigCapLines * m.lineH(9);

  var pageNo = 0;
  final pages = <pw.Page>[];
  for (final form in forms) {
    final colW = _widths(form.columns, tableW);
    final dense = form.columns.length > 12;
    final baseSize = dense ? 9.0 : 10.5;
    final headSize = dense ? 8.5 : 10.0;

    final titleH = m.lineH(13) * m.lines(m.bold, form.h1, 13, contentW) +
        m.lineH(12) * m.lines(m.bold, form.h2, 12, contentW) +
        form.lines.fold<double>(0, (h, l) => h + m.lineH(11) * m.lines(m.regular, l, 11, contentW));
    final fundH = 14 + m.lineH(11) + 8;
    final acctText = form.accountability?.map((r) => r.text).join() ?? '';
    final acctH = form.accountability == null ? 0.0 : m.lineH(11) * m.lines(m.bold, acctText, 11, contentW - 33) + 8;
    final headH = _headerHeight(m, form.columns, colW, headSize);
    final avail = contentH - titleH - fundH - acctH - headH - 2 * _outer - 2;
    final rowH = avail / rowsPerPage;

    final chunks = <List<List<String>>>[];
    for (var i = 0; i < form.rows.length; i += rowsPerPage) {
      chunks.add(form.rows.sublist(i, math.min(i + rowsPerPage, form.rows.length)));
    }
    if (chunks.isEmpty) chunks.add([]);

    // row height per page: the last page also has to hold the signatures
    final heights = <double>[];
    for (var p = 0; p < chunks.length; p++) {
      final last = p == chunks.length - 1 && signers.isNotEmpty;
      final n = math.max(chunks[p].length, 1);
      heights.add(last && n * rowH + sigH > avail ? (avail - sigH) / n : rowH);
    }

    // the largest text size at which every cell fits its row, the same on every page
    var scale = 1.0;
    for (var s = 1.0; s >= 0.6 - 1e-9; s -= 0.05) {
      scale = s;
      final size = baseSize * s;
      var fits = true;
      for (var p = 0; p < chunks.length && fits; p++) {
        for (final row in chunks[p]) {
          for (var c = 0; c < row.length && fits; c++) {
            final f = form.columns[c].italic ? m.italic : m.regular;
            final need = m.lines(f, row[c], size, colW[c] - 2 * _padH) * m.lineH(size) + 2 * _padV;
            if (need > heights[p]) fits = false;
          }
        }
      }
      if (fits) break;
    }
    final cellSize = baseSize * scale;

    for (var p = 0; p < chunks.length; p++) {
      final lastOfForm = p == chunks.length - 1;
      final withSign = lastOfForm && signers.isNotEmpty;
      final rows = [...chunks[p]];
      if (!withSign) {
        while (rows.length < rowsPerPage) {
          rows.add(List.filled(form.columns.length, ''));
        }
      }
      pageNo++;
      final number = pageNo;
      pages.add(pw.Page(
        pageFormat: _format,
        margin: pw.EdgeInsets.zero,
        build: (ctx) => pw.Stack(children: [
          pw.Padding(
            padding: const pw.EdgeInsets.fromLTRB(_mL, _mT, _mR, _mB),
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.SizedBox(
                width: contentW,
                child: pw.Column(children: [
                  pw.Text(form.h1, textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
                  pw.Text(form.h2, textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                  for (final l in form.lines) pw.Text(l, textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 11)),
                ]),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.only(top: 14, bottom: 8),
                child: pw.Text(form.fund, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
              ),
              if (form.accountability != null)
                pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 8),
                  child: pw.RichText(
                    text: pw.TextSpan(style: const pw.TextStyle(fontSize: 11), children: [
                      pw.WidgetSpan(child: pw.SizedBox(width: 33)),
                      for (final r in form.accountability!)
                        pw.TextSpan(text: r.text, style: r.bold ? pw.TextStyle(fontWeight: pw.FontWeight.bold) : null),
                    ]),
                  ),
                ),
              pw.Container(
                width: contentW,
                padding: const pw.EdgeInsets.all(_outer),
                decoration: pw.BoxDecoration(border: pw.Border.all(width: _outer)),
                child: pw.Column(children: [
                  _header(form.columns, colW, headH, headSize, m),
                  for (var r = 0; r < rows.length; r++)
                    _row(form.columns, colW, rows[r], heights[p], cellSize, m.lineH(cellSize), last: r == rows.length - 1),
                ]),
              ),
              if (withSign)
                pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 28),
                  child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                    for (var i = 0; i < signers.length; i++) ...[
                      if (i > 0) pw.SizedBox(width: 32),
                      pw.Expanded(
                        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
                          pw.Text(signers[i].label, style: const pw.TextStyle(fontSize: 10.5)),
                          pw.Container(
                            height: 34,
                            decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: 0.75))),
                          ),
                          pw.SizedBox(height: 3),
                          pw.Text(signers[i].caption, textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 9)),
                        ]),
                      ),
                    ],
                  ]),
                ),
            ]),
          ),
          pw.Positioned(
            right: _mR,
            bottom: _mB / 2 - 6,
            child: pw.Text('$number', style: const pw.TextStyle(fontSize: 11)),
          ),
        ]),
      ));
    }
  }
  for (final p in pages) {
    doc.addPage(p);
  }
  return doc.save();
}

List<double> _widths(List<FormColumn> cols, double total) {
  final sum = cols.fold<double>(0, (s, c) => s + c.width);
  return [for (final c in cols) total * c.width / sum];
}

double _headerHeight(_Measure m, List<FormColumn> cols, List<double> w, double size) {
  final lh = m.lineH(size);
  var full = 0.0, groupTop = 0.0, groupSub = 0.0;
  for (var i = 0; i < cols.length; i++) {
    final lines = m.lines(m.bold, cols[i].label, size, w[i] - 6);
    if (cols[i].group == null) {
      full = math.max(full, lines * lh + 8);
    } else {
      groupSub = math.max(groupSub, lines * lh + 8);
    }
  }
  for (final g in {for (final c in cols) if (c.group != null) c.group!}) {
    var gw = 0.0;
    for (var i = 0; i < cols.length; i++) {
      if (cols[i].group == g) gw += w[i];
    }
    groupTop = math.max(groupTop, m.lines(m.bold, g, size, gw - 6) * lh + 8);
  }
  return math.max(full, groupTop + groupSub);
}

pw.Border _cellBorder({required bool right, required bool bottom}) => pw.Border(
      right: right ? const pw.BorderSide(width: _inner) : pw.BorderSide.none,
      bottom: bottom ? const pw.BorderSide(width: _inner) : pw.BorderSide.none,
    );

pw.Widget _headCell(String text, double w, double h, double size, {required bool right}) => pw.Container(
      width: w,
      height: h,
      alignment: pw.Alignment.center,
      padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 4),
      decoration: pw.BoxDecoration(border: _cellBorder(right: right, bottom: true)),
      child: pw.Text(text, textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: size, fontWeight: pw.FontWeight.bold)),
    );

pw.Widget _header(List<FormColumn> cols, List<double> w, double h, double size, _Measure m) {
  final children = <pw.Widget>[];
  var i = 0;
  while (i < cols.length) {
    final g = cols[i].group;
    if (g == null) {
      children.add(_headCell(cols[i].label, w[i], h, size, right: i < cols.length - 1));
      i++;
      continue;
    }
    var j = i;
    var gw = 0.0;
    while (j < cols.length && cols[j].group == g) {
      gw += w[j];
      j++;
    }
    final subLines = [for (var k = i; k < j; k++) m.lines(m.bold, cols[k].label, size, w[k] - 6)].reduce(math.max);
    final subH = subLines * m.lineH(size) + 8;
    final from = i, to = j;
    children.add(pw.SizedBox(
      width: gw,
      height: h,
      child: pw.Column(children: [
        _headCell(g, gw, h - subH, size, right: to < cols.length),
        pw.Row(children: [
          for (var k = from; k < to; k++) _headCell(cols[k].label, w[k], subH, size, right: k < cols.length - 1),
        ]),
      ]),
    ));
    i = j;
  }
  return pw.Row(children: children);
}

pw.Widget _row(List<FormColumn> cols, List<double> w, List<String> values, double h, double size, double lineH,
    {required bool last}) {
  final maxLines = math.max(1, ((h - 2 * _padV) / lineH).floor());
  return pw.Row(children: [
    for (var c = 0; c < cols.length; c++)
      pw.Container(
        width: w[c],
        height: h,
        padding: const pw.EdgeInsets.symmetric(horizontal: _padH, vertical: _padV),
        alignment: cols[c].align == 'r'
            ? pw.Alignment.topRight
            : cols[c].align == 'c'
                ? pw.Alignment.topCenter
                : pw.Alignment.topLeft,
        decoration: pw.BoxDecoration(border: _cellBorder(right: c < cols.length - 1, bottom: !last)),
        child: pw.Text(
          c < values.length ? values[c] : '',
          maxLines: maxLines,
          overflow: pw.TextOverflow.clip,
          textAlign: cols[c].align == 'r'
              ? pw.TextAlign.right
              : cols[c].align == 'c'
                  ? pw.TextAlign.center
                  : pw.TextAlign.left,
          style: pw.TextStyle(fontSize: size, fontStyle: cols[c].italic ? pw.FontStyle.italic : pw.FontStyle.normal),
        ),
      ),
  ]);
}
