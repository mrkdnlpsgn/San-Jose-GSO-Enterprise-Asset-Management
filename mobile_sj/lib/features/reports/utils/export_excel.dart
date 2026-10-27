// Excel exports, sheet for sheet the same as the web Reports page's: a plain table for the
// Condition Report, Maintenance Ledger and IIRUP, and a form per sheet for the RPCPPE (a type
// of PPE each), PAR (a PAR each) and Property Card (a card each). Shared like any other file.

import 'dart:io';

import 'package:excel/excel.dart' as xl;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'report_format.dart';

/// One cell: a number stays a number (summed, formatted in Excel), anything else is text.
xl.CellValue? cellOf(Object? v) {
  if (v == null || v == '') return null;
  if (v is int) return xl.IntCellValue(v);
  if (v is num) return xl.DoubleCellValue(v.toDouble());
  return xl.TextCellValue(v.toString());
}

/// A sheet built from rows of values ("array of arrays"), with merged ranges and column widths.
class SheetSpec {
  final String name;
  final List<List<Object?>> rows;
  final List<double> widths;
  /// [firstRow, firstCol, lastRow, lastCol]
  final List<List<int>> merges;
  /// cells (row, col) shown as #,##0.00
  final List<(int, int)> money;
  const SheetSpec(this.name, this.rows, {this.widths = const [], this.merges = const [], this.money = const []});
}

Future<void> shareWorkbook(String fileName, List<SheetSpec> sheets) async {
  final book = xl.Excel.createExcel();
  final used = <String>{};
  for (final spec in sheets) {
    var name = safeName(spec.name);
    if (name.length > 31) name = name.substring(0, 31);
    for (var n = 2; used.contains(name.toUpperCase()); n++) {
      final base = safeName(spec.name);
      name = '${base.length > 27 ? base.substring(0, 27) : base} ($n)';
    }
    used.add(name.toUpperCase());
    final sheet = book[name];
    for (final row in spec.rows) {
      sheet.appendRow([for (final v in row) cellOf(v)]);
    }
    for (var c = 0; c < spec.widths.length; c++) {
      sheet.setColumnWidth(c, spec.widths[c]);
    }
    for (final (r, c) in spec.money) {
      final cell = sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r));
      if (cell.value is xl.DoubleCellValue || cell.value is xl.IntCellValue) {
        cell.cellStyle = xl.CellStyle(numberFormat: xl.NumFormat.standard_4);
      }
    }
    for (final mg in spec.merges) {
      sheet.merge(xl.CellIndex.indexByColumnRow(columnIndex: mg[1], rowIndex: mg[0]),
          xl.CellIndex.indexByColumnRow(columnIndex: mg[3], rowIndex: mg[2]));
    }
  }
  final first = book.getDefaultSheet();
  if (first != null && !used.contains(first.toUpperCase())) book.delete(first);
  if (used.isNotEmpty) book.setDefaultSheet(book.tables.keys.first);

  final bytes = book.save();
  if (bytes == null) return;
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$fileName');
  await file.writeAsBytes(bytes, flush: true);
  await SharePlus.instance.share(ShareParams(files: [XFile(file.path)], subject: fileName));
}

String stampToday() => todayKey();

/// A plain table: a header row of labels, then one row per record (the web's json_to_sheet).
Future<void> exportTable(String title, List<String> labels, List<List<Object?>> rows) {
  final widths = [
    for (var c = 0; c < labels.length; c++)
      ([labels[c].length, for (final r in rows) str(r[c]).length].reduce((a, b) => a > b ? a : b) + 2).toDouble(),
  ];
  return shareWorkbook('${safeName(title).replaceAll(RegExp(r'\s+'), '_')}_${stampToday()}.xlsx', [
    SheetSpec(title, [labels, ...rows], widths: widths),
  ]);
}
