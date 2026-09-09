import 'dart:io';
import 'package:excel/excel.dart' as xl;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../model/asset_model.dart';

// Import columns — keys must match the backend's AssetImportRow fields
// exactly (see backend_sj/.../dto/AssetImportRow.java), and mirror the web
// Assets page's import template (assetExcel.js) column-for-column.
const importColumns = [
  (key: 'description', label: 'Description'),
  (key: 'categoryName', label: 'Category'),
  (key: 'quantity', label: 'Qty (Property Card)'),
  (key: 'physicalCount', label: 'Qty (Physical Count)'),
  (key: 'acquisitionDate', label: 'Acquisition Date'),
  (key: 'unitValue', label: 'Unit Value'),
  (key: 'officeName', label: 'Office'),
  (key: 'accountablePerson', label: 'Accountable Person'),
  (key: 'location', label: 'Location'),
  (key: 'condition', label: 'Condition'),
  (key: 'remarks', label: 'Remarks'),
];

const Map<String, String> _headerMap = {
  'description': 'description',
  'category': 'categoryName',
  'category name': 'categoryName',
  'qty (property card)': 'quantity',
  'qty property card': 'quantity',
  'quantity': 'quantity',
  'property card qty': 'quantity',
  'qty (physical count)': 'physicalCount',
  'qty physical count': 'physicalCount',
  'physical count': 'physicalCount',
  'acquisition date': 'acquisitionDate',
  'date acquired': 'acquisitionDate',
  'date': 'acquisitionDate',
  'unit value': 'unitValue',
  'unit value (php)': 'unitValue',
  'amount': 'unitValue',
  'office': 'officeName',
  'office name': 'officeName',
  'location (office)': 'officeName',
  'accountable person': 'accountablePerson',
  'location': 'location',
  'physical location': 'location',
  'condition': 'condition',
  'remarks': 'remarks',
};

Future<void> downloadImportTemplate() async {
  final workbook = xl.Excel.createExcel();
  const sheetName = 'Assets';
  final sheet = workbook[sheetName];
  workbook.setDefaultSheet(sheetName);
  sheet.appendRow(importColumns.map((c) => xl.TextCellValue(c.label)).toList());

  final bytes = workbook.save();
  if (bytes == null) return;

  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/assets_import_template.xlsx');
  await file.writeAsBytes(bytes, flush: true);
  await SharePlus.instance.share(ShareParams(files: [XFile(file.path)], subject: 'Assets Import Template'));
}

class AssetImportParseException implements Exception {
  final String message;
  const AssetImportParseException(this.message);
  @override
  String toString() => message;
}

// Reads an .xlsx file's bytes and returns a list of row maps keyed the same
// way AssetService.bulkImport() expects. Throws AssetImportParseException
// with a user-facing message on anything that isn't a valid, recognisable
// spreadsheet.
List<Map<String, String>> parseAssetImportBytes(List<int> bytes) {
  late final xl.Excel workbook;
  try {
    workbook = xl.Excel.decodeBytes(bytes);
  } catch (_) {
    throw const AssetImportParseException('Failed to read the file. Make sure it is a valid XLSX file.');
  }

  if (workbook.tables.isEmpty) {
    throw const AssetImportParseException('The file has no sheets.');
  }
  final sheet = workbook.tables[workbook.tables.keys.first]!;
  final rows = sheet.rows;
  if (rows.length < 2) {
    throw const AssetImportParseException('The file is empty or contains no data rows.');
  }

  final headers = rows.first.map((c) => (c?.value?.toString() ?? '').trim().toLowerCase()).toList();
  final mappedHeaders = headers.map((h) => _headerMap[h]).toList();
  if (!mappedHeaders.any((k) => k != null)) {
    throw const AssetImportParseException(
        'No recognised columns found. Download the template to see the expected headers.');
  }

  final parsed = <Map<String, String>>[];
  for (final row in rows.skip(1)) {
    final values = List.generate(
        mappedHeaders.length, (i) => i < row.length ? (row[i]?.value?.toString() ?? '').trim() : '');
    if (values.every((v) => v.isEmpty)) continue;

    final obj = <String, String>{};
    for (var i = 0; i < mappedHeaders.length; i++) {
      final key = mappedHeaders[i];
      if (key != null) obj[key] = values[i];
    }
    parsed.add(obj);
  }

  if (parsed.isEmpty) {
    throw const AssetImportParseException('No data rows found in the file.');
  }
  return parsed;
}

Future<void> exportAssetsToExcel(List<AssetModel> assets) async {
  final workbook = xl.Excel.createExcel();
  const sheetName = 'Assets';
  final sheet = workbook[sheetName];
  workbook.setDefaultSheet(sheetName);

  const headers = [
    'Property No.', 'Description', 'Category', 'Qty (Property Card)', 'Qty (Physical Count)',
    'Shortage/Overage Qty', 'Shortage/Overage Value', 'Unit Value', 'Office', 'Accountable Person',
    'Location', 'Acquisition Date', 'Condition', 'Lifecycle Status', 'Remarks',
  ];
  sheet.appendRow(headers.map((h) => xl.TextCellValue(h)).toList());

  for (final a in assets) {
    final diff = a.physicalCount != null ? a.physicalCount! - a.quantity : null;
    final diffValue = diff != null ? diff * a.unitValue : null;
    sheet.appendRow([
      xl.TextCellValue(a.propertyNumber),
      xl.TextCellValue(a.description),
      xl.TextCellValue(a.category.categoryName),
      xl.TextCellValue(a.quantity.toString()),
      xl.TextCellValue(a.physicalCount?.toString() ?? ''),
      xl.TextCellValue(diff?.toString() ?? ''),
      xl.TextCellValue(diffValue?.toStringAsFixed(2) ?? ''),
      xl.TextCellValue(a.unitValue.toStringAsFixed(2)),
      xl.TextCellValue(a.office.officeName),
      xl.TextCellValue(a.accountablePerson ?? ''),
      xl.TextCellValue(a.location),
      xl.TextCellValue(a.acquisitionDate),
      xl.TextCellValue(a.condition),
      xl.TextCellValue(a.lifecycleStatus),
      xl.TextCellValue(a.remarks ?? ''),
    ]);
  }

  final bytes = workbook.save();
  if (bytes == null) return;

  final dir = await getTemporaryDirectory();
  final stamp = DateTime.now().toIso8601String().substring(0, 10);
  final file = File('${dir.path}/assets_export_$stamp.xlsx');
  await file.writeAsBytes(bytes, flush: true);
  await SharePlus.instance.share(ShareParams(files: [XFile(file.path)], subject: 'Assets Export'));
}
