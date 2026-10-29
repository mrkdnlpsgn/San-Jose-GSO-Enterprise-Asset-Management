// The reports, one for one with the web Reports page (frontend pages/Reports/index.jsx): the
// same reports in the same order, reading the same API data, with the same columns, filters and
// exports. A change there should be made here too.

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart' show PdfPageFormat;

import '../../../core/api/api_client.dart';
import '../model/report_definition.dart';
import '../utils/export_excel.dart';
import '../utils/forms_pdf.dart';
import '../utils/maintenance_card.dart';
import '../utils/print_form.dart';
import '../utils/report_format.dart';

// Reports need the full dataset, not a page of it: the backend's page size is 20, so ask for
// enough to always cover a municipal office's inventory in one request.
Future<List<ReportRow>> _fetch(String path, {bool paged = true}) async {
  final res = await ApiClient.instance.dio.get(path, queryParameters: paged ? {'size': 100000} : null);
  return [for (final r in res.data as List) Map<String, dynamic>.from(r as Map)];
}

// The forecast and depreciation endpoints answer with totals plus an `items` list (the rows).
Future<List<ReportRow>> _fetchItems(String path, Map<String, dynamic> params) async {
  final res = await ApiClient.instance.dio.get(path, queryParameters: {...params, 'items': true});
  return [for (final r in (res.data as Map)['items'] as List) Map<String, dynamic>.from(r as Map)];
}

num _lineAmount(ReportRow r) => toNum(r['unitValue']) * toNum(r['quantity'], 1);
String _uniqueJoined(List<ReportRow> rows, Object? Function(ReportRow) pick) =>
    {for (final r in rows) str(pick(r))}.where((s) => s.isNotEmpty).join(', ');
String _orNa(Object? v) => str(v).isEmpty ? 'N/A' : str(v);
String _fixed(Object? v) => v == null || v == '' ? '' : toNum(v).toStringAsFixed(2);

// Repairs & Maintenance Forecast: next year (Manila time), and the 3 full years before this one
// plus this year so far - the same years as MaintenanceForecastService.
int _forecastYear() => DateTime.now().toUtc().add(const Duration(hours: 8)).year + 1;
List<String> _forecastHistory() => [for (var y = _forecastYear() - 4; y < _forecastYear(); y++) '$y'];
const _trendLabel = {'RISING': 'Rising', 'FALLING': 'Falling', 'STEADY': 'Steady'};

// ── RPCPPE ───────────────────────────────────────────────────────────────────

const rpcppeDefaults = <String, String>{
  'asAt': '',
  'fundCluster': 'General Fund',
  'officer': 'REGIE B. AGNO',
  'designation': 'Municipal General Services Officer',
  'entity': 'Municipality of San Jose, Batangas',
  'assumedOn': '2018-12-01',
};

/// One report line per asset, in the form's column order.
Map<String, Object> rpcppeLine(ReportRow a) {
  final so = toNum(a['shortageOverageQty']);
  final soValue = toNum(a['shortageOverageValue']);
  return {
    'article': str(at(a, 'article.articleName')),
    'location': str(at(a, 'office.officeName')),
    'description': str(a['description']),
    'propertyNumber': str(a['propertyNumber']),
    'unit': 'unit',
    'unitValue': a['unitValue'] != null ? toNum(a['unitValue']) : '',
    'qtyCard': a['quantity'] ?? 1,
    'qtyCount': a['physicalCount'] ?? '',
    // like the paper form, shortage/overage stays blank when nothing was found
    'soQty': so != 0 ? so : '',
    'soValue': so != 0 || soValue != 0 ? soValue : '',
    'remarks': str(a['condition']).toLowerCase(),
  };
}

/// Items on hand as at the report date, sorted the way the form lists them.
List<ReportRow> rpcppeRows(List<ReportRow> assets, String asAt) {
  final rows = assets.where((a) {
    final d = str(a['acquisitionDate']);
    return asAt.isEmpty || d.isEmpty || d.compareTo(asAt) <= 0;
  }).toList();
  int cmp(String a, String b) => a.compareTo(b);
  rows.sort((x, y) {
    final ax = str(at(x, 'article.articleName')), ay = str(at(y, 'article.articleName'));
    final r = cmp(ax.isEmpty ? '￿' : ax, ay.isEmpty ? '￿' : ay);
    if (r != 0) return r;
    final o = cmp(str(at(x, 'office.officeName')), str(at(y, 'office.officeName')));
    return o != 0 ? o : cmp(str(x['propertyNumber']), str(y['propertyNumber']));
  });
  return rows;
}

String _asAtText(Map<String, String> s) =>
    'As at ${longDate(s['asAt']).isNotEmpty ? longDate(s['asAt']) : longDate(todayKey())}';

const _blank = '________________';
String _orBlank(String? v) => (v ?? '').isEmpty ? _blank : v!;

String _accountability(Map<String, String> s) =>
    'For which ${_orBlank(s['officer'])}, ${_orBlank(s['designation'])}, ${_orBlank(s['entity'])} is accountable, '
    'having assumed such accountability on ${_orBlank(longDate(s['assumedOn']))}.';

/// The printed form sets the officer and the date in bold.
List<TextRun> _accountabilityRuns(Map<String, String> s) => [
      const TextRun('For which '),
      TextRun('${_orBlank(s['officer'])}, ${_orBlank(s['designation'])}, ${_orBlank(s['entity'])}', bold: true),
      const TextRun(' is accountable, having assumed such accountability on '),
      TextRun(_orBlank(longDate(s['assumedOn'])), bold: true),
      const TextRun('.'),
    ];

// Column widths (%) measured from the GSO's printed form.
const _rpcppeColumns = [
  FormColumn('ARTICLE', width: 7),
  FormColumn('LOCATION', width: 8),
  FormColumn('DESCRIPTION', width: 17),
  FormColumn('PROPERTY NUMBER', width: 11, align: 'c'),
  FormColumn('UNIT OF MEASURE', width: 8, align: 'c'),
  FormColumn('UNIT VALUE', width: 10, align: 'r'),
  FormColumn('QUANTITY per PROPERTY CARD', width: 8, align: 'c'),
  FormColumn('QUANTITY per PHYSICAL COUNT', width: 8, align: 'c'),
  FormColumn('Quantity', group: 'SHORTAGE/ OVERAGE', width: 6, align: 'c'),
  FormColumn('Value', group: 'SHORTAGE/ OVERAGE', width: 6, align: 'r'),
  FormColumn('REMARKS', width: 11, italic: true),
];

const _rpcppeSigners = [
  StdSigner('Certified Correct by:', 'Signature over Printed Name of Inventory Committee Chair and Members'),
  StdSigner('Approved by:', 'Signature over Printed Name of Head of Agency/Entity or Authorized Representative'),
  StdSigner('Verified by:', 'Signature over Printed Name of COA Representative'),
];

String _moneyOrBlank(Object? v) => v == '' || v == null ? '' : money(toNum(v));

Future<void> printRpcppe(List<PickItem> groups, Map<String, String> settings) {
  final s = {...rpcppeDefaults, ...settings};
  final forms = [
    for (final g in groups)
      StdForm(
        h1: 'REPORT ON THE PHYSICAL COUNT OF PROPERTY, PLANT AND EQUIPMENT',
        h2: str(g['categoryName']).toUpperCase(),
        lines: ['(Type of Property, Plant and Equipment)', _asAtText(s)],
        fund: 'Fund Cluster : ${(s['fundCluster'] ?? '').toUpperCase()}',
        accountability: _accountabilityRuns(s),
        columns: _rpcppeColumns,
        rows: [
          for (final a in g.rows)
            () {
              final l = rpcppeLine(a);
              return [
                str(l['article']), str(l['location']), str(l['description']), str(l['propertyNumber']), 'unit',
                _moneyOrBlank(l['unitValue']), str(l['qtyCard']), str(l['qtyCount']), str(l['soQty']),
                _moneyOrBlank(l['soValue']), str(l['remarks']),
              ];
            }(),
        ],
      ),
  ];
  final title = 'RPCPPE ${_asAtText(s)}';
  return printPdf(title, (fonts) => buildStandardPdf(title, forms, _rpcppeSigners, fonts));
}

Future<void> exportRpcppeExcel(List<PickItem> groups, Map<String, String> settings) {
  final s = {...rpcppeDefaults, ...settings};
  final sheets = <SheetSpec>[];
  for (final g in groups) {
    final rows = <List<Object?>>[
      ['REPORT ON THE PHYSICAL COUNT OF PROPERTY, PLANT AND EQUIPMENT'],
      [str(g['categoryName']).toUpperCase()],
      ['(Type of Property, Plant and Equipment)'],
      [_asAtText(s)],
      [],
      ['Fund Cluster : ${(s['fundCluster'] ?? '').toUpperCase()}'],
      [_accountability(s)],
      [],
      ['ARTICLE', 'LOCATION', 'DESCRIPTION', 'PROPERTY NUMBER', 'UNIT OF MEASURE', 'UNIT VALUE',
        'QUANTITY per PROPERTY CARD', 'QUANTITY per PHYSICAL COUNT', 'SHORTAGE/OVERAGE', '', 'REMARKS'],
      ['', '', '', '', '', '', '', '', 'Quantity', 'Value', ''],
    ];
    for (final a in g.rows) {
      final l = rpcppeLine(a);
      rows.add([l['article'], l['location'], l['description'], l['propertyNumber'], l['unit'],
        l['unitValue'] == '' ? '' : double.parse(toNum(l['unitValue']).toStringAsFixed(2)), l['qtyCard'], l['qtyCount'],
        l['soQty'], l['soValue'] == '' ? '' : double.parse(toNum(l['soValue']).toStringAsFixed(2)), l['remarks']]);
    }
    rows.addAll([
      [], ['Certified Correct by:', '', '', '', 'Approved by:', '', '', '', 'Verified by:'], [], [],
      ['Signature over Printed Name of Inventory Committee Chair and Members', '', '', '',
        'Signature over Printed Name of Head of Agency/Entity or Authorized Representative', '', '', '',
        'Signature over Printed Name of COA Representative'],
    ]);
    List<int> full(int r) => [r, 0, r, 10];
    sheets.add(SheetSpec(
      str(g['categoryName']),
      rows,
      widths: const [14, 16, 30, 20, 10, 14, 12, 12, 10, 12, 14],
      merges: [full(0), full(1), full(2), full(3), full(5), full(6),
        for (final c in [0, 1, 2, 3, 4, 5, 6, 7, 10]) [8, c, 9, c], [8, 8, 8, 9]],
      money: [for (var r = 10; r < 10 + g.rows.length; r++) ...[(r, 5), (r, 9)]],
    ));
  }
  final stamp = (s['asAt'] ?? '').isNotEmpty ? s['asAt']! : stampToday();
  final one = groups.length == 1 ? '${str(groups[0]['categoryName']).replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')}_' : '';
  return shareWorkbook('RPCPPE_$one$stamp.xlsx', sheets);
}

/// One RPCPPE form per type of PPE (category), with the items on hand as at the report date.
List<PickItem> rpcppeGroupsOf(List<ReportRow> assets, Map<String, String> settings) {
  final byCat = <String, List<ReportRow>>{};
  final names = <String, String>{};
  for (final a in rpcppeRows(assets, settings['asAt'] ?? '')) {
    final key = str(at(a, 'category.id')).isEmpty ? 'none' : str(at(a, 'category.id'));
    names[key] = str(at(a, 'category.categoryName')).isEmpty ? 'Uncategorized' : str(at(a, 'category.categoryName'));
    byCat.putIfAbsent(key, () => []).add(a);
  }
  final items = [
    for (final e in byCat.entries)
      PickItem(e.key, {'categoryName': names[e.key], 'total': e.value.fold<num>(0, (n, a) => n + _lineAmount(a))}, e.value),
  ]..sort((a, b) => str(a['categoryName']).compareTo(str(b['categoryName'])));
  return items;
}

// One RPCPPE line, as listed under an expanded type of PPE (same columns as the printed form).
final _rpcppeHeaders = [
  ReportColumn('Article', display: (a) => _orNa(rpcppeLine(a)['article']), raw: (a) => rpcppeLine(a)['article']),
  ReportColumn('Location', display: (a) => _orNa(rpcppeLine(a)['location']), raw: (a) => rpcppeLine(a)['location']),
  ReportColumn('Description', display: (a) => _orNa(rpcppeLine(a)['description']), raw: (a) => rpcppeLine(a)['description']),
  ReportColumn('Property No.', display: (a) => _orNa(rpcppeLine(a)['propertyNumber']), raw: (a) => rpcppeLine(a)['propertyNumber']),
  ReportColumn('Unit', display: (_) => 'unit', raw: (_) => 'unit'),
  ReportColumn('Unit Value', display: (a) => rMoney(a['unitValue']), raw: (a) => a['unitValue']),
  ReportColumn('Qty (Card)', display: (a) => str(rpcppeLine(a)['qtyCard']), raw: (a) => rpcppeLine(a)['qtyCard']),
  ReportColumn('Qty (Count)', display: (a) => str(rpcppeLine(a)['qtyCount']), raw: (a) => rpcppeLine(a)['qtyCount']),
  ReportColumn('Shortage/Overage', display: (a) {
    final l = rpcppeLine(a);
    return l['soQty'] == '' ? '' : '${l['soQty']} · ${rMoney(l['soValue'])}';
  }, raw: (a) => rpcppeLine(a)['soQty']),
  ReportColumn('Remarks', display: (a) => str(rpcppeLine(a)['remarks']), raw: (a) => rpcppeLine(a)['remarks']),
];

// ── PAR ──────────────────────────────────────────────────────────────────────

const _parEntity = 'San Jose, Batangas';
const _parFund = 'General Fund';

// PAR numbers are compared trimmed and case-insensitive, matching how the Assets search treats them.
String _normPar(Object? v) => str(v).trim().toUpperCase();

List<String> _parDescriptionLines(ReportRow a) {
  final specs = str(a['specifications']).split(RegExp(r'\r?\n')).map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
  final brand = RegExp(r'^(brand|model)\s*:', caseSensitive: false);
  final ident = specs.where((l) => brand.hasMatch(l)).toList();
  final rest = specs.where((l) => !brand.hasMatch(l)).toList();
  final lines = [str(a['description']).isEmpty ? 'N/A' : str(a['description']), ...ident];
  if (str(a['serialNumber']).isNotEmpty) lines.add('S/N: ${a['serialNumber']}');
  if (rest.isNotEmpty) lines.addAll(['', 'Technical Specifications:', ...rest]);
  return lines;
}

Map<String, Object> _parHeader(List<ReportRow> rows) {
  final office = _uniqueJoined(rows, (r) => at(r, 'office.officeName'));
  return {
    'office': office.isEmpty ? 'No office assigned' : office,
    'receivedBy': _uniqueJoined(rows, (r) => at(r, 'accountablePerson.fullName')),
    'total': rows.fold<num>(0, (s, r) => s + _lineAmount(r)),
  };
}

/// One entry per distinct PAR number in the loaded assets, newest PAR first.
List<PickItem> parGroupsOf(List<ReportRow> assets) {
  final byKey = <String, List<ReportRow>>{};
  final pars = <String, String>{};
  for (final a in assets) {
    final key = _normPar(a['parNumber']);
    if (key.isEmpty) continue;
    pars.putIfAbsent(key, () => str(a['parNumber']).trim());
    byKey.putIfAbsent(key, () => []).add(a);
  }
  return [
    for (final e in byKey.entries)
      PickItem(e.key, {'par': pars[e.key], ..._parHeader(e.value)}, e.value),
  ]..sort((a, b) => str(b['par']).compareTo(str(a['par'])));
}

final _parHeaders = [
  ReportColumn('Qty', display: (r) => str(r['quantity'] ?? 1), raw: (r) => r['quantity'] ?? 1),
  ReportColumn('Description', display: (r) => _orNa(r['description']), raw: (r) => str(r['description'])),
  ReportColumn('Serial No.', display: (r) => _orNa(r['serialNumber']), raw: (r) => str(r['serialNumber'])),
  ReportColumn('Property No.', display: (r) => _orNa(r['propertyNumber']), raw: (r) => str(r['propertyNumber'])),
  ReportColumn('Date Acquired', display: (r) => rDate(r['acquisitionDate']), raw: (r) => str(r['acquisitionDate'])),
  ReportColumn('Unit Cost', display: (r) => rMoney(r['unitValue']), raw: (r) => _fixed(r['unitValue'])),
  ReportColumn('Amount', display: (r) => rMoney(_lineAmount(r)), raw: (r) => _lineAmount(r).toStringAsFixed(2)),
];

Future<void> printPar(List<PickItem> groups) {
  final title = groups.length == 1 ? 'PAR No. ${groups[0]['par']}' : 'PAR Forms (${groups.length})';
  final forms = [
    for (final g in groups)
      ParForm(
        par: str(g['par']),
        office: str(g['office']),
        entity: _parEntity,
        fund: _parFund,
        receivedBy: str(g['receivedBy']),
        total: rMoney(g['total']),
        lines: [
          for (final a in g.rows)
            ParLine(str(a['quantity'] ?? 1), _parDescriptionLines(a), str(a['propertyNumber']), rDate(a['acquisitionDate']),
                rMoney(_lineAmount(a))),
        ],
      ),
  ];
  return printPdf(title, (fonts) => buildParPdf(title, forms, fonts), format: PdfPageFormat.a4);
}

Future<void> exportParExcel(List<PickItem> groups) {
  final sheets = [
    for (final g in groups)
      () {
        final rows = <List<Object?>>[
          ['PROPERTY ACKNOWLEDGMENT RECEIPT'],
          ['(${str(g['office']).toUpperCase()})'],
          [],
          ['Entity Name', '', ': $_parEntity', '', 'PAR No.', ': ${g['par']}'],
          ['Fund Cluster', '', ': $_parFund'],
          [],
          ['Quantity', 'Unit', 'Description', 'Property Number', 'Date Acquired', 'Amount'],
        ];
        for (final a in g.rows) {
          final lines = _parDescriptionLines(a);
          for (var i = 0; i < lines.length; i++) {
            rows.add(i == 0
                ? [a['quantity'] ?? 1, 'Unit', lines[i], str(a['propertyNumber']), str(a['acquisitionDate']),
                    double.parse(_lineAmount(a).toStringAsFixed(2))]
                : ['', '', lines[i], '', '', '']);
          }
        }
        rows.add(['', '', '', '', 'TOTAL', double.parse(toNum(g['total']).toStringAsFixed(2))]);
        rows.addAll([
          [], ['Received by:', '', '', 'Issued by:'], [], ['', '', str(g['receivedBy']), '', '', ''],
          ['', '', 'Signature over Printed Name of End User', '', 'Signature over Printed Name of Supply and/or Property Custodian'],
          [], ['', '', 'Position/Office', '', 'Position/Office'], [], ['', '', 'Date', '', 'Date'],
        ]);
        return SheetSpec('PAR ${g['par']}', rows,
            widths: const [10, 8, 60, 24, 16, 16],
            merges: const [[0, 0, 0, 5], [1, 0, 1, 5]]);
      }(),
  ];
  final file = groups.length == 1 ? 'PAR_${safeName(str(groups[0]['par']))}' : 'PAR_Forms_${groups.length}';
  return shareWorkbook('${file}_${stampToday()}.xlsx', sheets);
}

// ── Property Card ────────────────────────────────────────────────────────────

const _cardEntity = 'SAN JOSE BATANGAS';

String _cardDate(Object? d) {
  final k = manilaDateKey(d);
  if (k.length != 10) return '';
  return '${k.substring(5, 7)}/${k.substring(8, 10)}/${k.substring(0, 4)}';
}

String _cardMoney(Object? v) => v == null || v == '' ? '' : rMoney(v);

// Description cell lines: the receipt line also carries the amount, like the paper card.
List<String> _cardDescription(PickItem card, Map e) => e['kind'] == 'RECEIPT'
    ? [str(e['description']), _cardMoney(card['unitValue'])].where((s) => s.isNotEmpty).toList()
    : [str(e['description'])];

List<Map> _entries(PickItem c) => [for (final e in (c['entries'] as List? ?? const [])) e as Map];

Future<void> printPropertyCards(List<PickItem> cards) {
  final title = cards.length == 1 ? 'Property Card ${cards[0]['propertyNumber']}' : 'Property Cards (${cards.length})';
  final forms = [
    for (final c in cards)
      CardForm(str(c['category']), [
        for (final e in _entries(c))
          [_cardDate(e['date']), str(e['reference']), _cardDescription(c, e).join('\n'), str(e['receiptQty']),
            str(e['transferTo']), str(e['office']), str(e['balanceQty'])],
      ]),
  ];
  return printPdf(title, (fonts) => buildPropertyCardPdf(title, _cardEntity, forms, fonts), format: PdfPageFormat.a4);
}

Future<void> exportPropertyCardsExcel(List<PickItem> cards) {
  final sheets = [
    for (final c in cards)
      SheetSpec(str(c['propertyNumber']), [
        ['PROPERTY CARD'],
        [_cardEntity],
        ['LGU'],
        ['Plant, Property and Equipment: ${str(c['category'])}', '', '', '', 'Property Classification:'],
        ['Date', 'Reference Property #', 'Description', 'Receipt Qty', 'Transfer', 'Office', 'Balance Qty'],
        for (final e in _entries(c))
          [str(e['date']), str(e['reference']), _cardDescription(c, e).join('\n'), e['receiptQty'] ?? '',
            str(e['transferTo']), str(e['office']), e['balanceQty']],
      ], widths: const [12, 30, 44, 11, 26, 34, 11], merges: const [
        [0, 0, 0, 6], [1, 0, 1, 6], [2, 0, 2, 6], [3, 0, 3, 3], [3, 4, 3, 6],
      ]),
  ];
  final file = cards.length == 1
      ? 'Property_Card_${safeName(str(cards[0]['propertyNumber']))}'
      : 'Property_Cards_${cards.length}';
  return shareWorkbook('${file}_${stampToday()}.xlsx', sheets);
}

final _cardEntryHeaders = [
  ReportColumn('Date', display: (e) => rDate(e['date']), raw: (e) => e['date']),
  ReportColumn('Reference Property #', display: (e) => _orNa(e['reference']), raw: (e) => e['reference']),
  ReportColumn('Description', display: (e) => _orNa(e['description']), raw: (e) => e['description']),
  ReportColumn('Receipt Qty', display: (e) => str(e['receiptQty']), raw: (e) => e['receiptQty']),
  ReportColumn('Transfer', display: (e) => _orNa(e['transferTo']), raw: (e) => e['transferTo']),
  ReportColumn('Office', display: (e) => _orNa(e['office']), raw: (e) => e['office']),
  ReportColumn('Balance Qty', display: (e) => str(e['balanceQty']), raw: (e) => e['balanceQty']),
];

// ── Plain reports (Condition, Maintenance, IIRUP) ────────────────────────────

final _isoDate = RegExp(r'^\d{4}-\d{2}-\d{2}(T[\d:.]+)?$');
final _money = RegExp(r'^-?\d+\.\d{2}$');
final _int = RegExp(r'^\d+$');

/// A raw value as the printout shows it, and how it sits in its cell.
(String, String) printCell(Object? v) {
  final s = str(v);
  if (_isoDate.hasMatch(s)) return (rDate(s), 'c');
  if (_money.hasMatch(s)) return (money(num.parse(s)), 'r');
  if (_int.hasMatch(s)) return (s, 'c');
  return (s, 'l');
}

/// Printed in the standard (RPCPPE) format: the title block and table header on every page,
/// at most 8 rows a page, and the report's signatures after the last page.
Future<void> printTable(ReportDefinition report, List<ReportRow> rows, String from, String to, Map<String, String> settings) {
  final s = {...rpcppeDefaults, ...settings};
  final today = todayKey();
  final period = from.isNotEmpty
      ? 'For the period ${longDate(from)} to ${longDate(to.isNotEmpty ? to : today)}'
      : 'As at ${longDate(to.isNotEmpty ? to : today)}';
  final cells = [for (final r in rows) [for (final h in report.headers) printCell(h.raw(r))]];
  // a column sits the way its values do (dates centred, amounts right)
  final columns = [
    for (var c = 0; c < report.headers.length; c++)
      FormColumn(report.headers[c].label.toUpperCase(),
          width: report.headers[c].printWidth ?? 1,
          align: cells.map((r) => r[c]).firstWhere((v) => v.$1.isNotEmpty, orElse: () => ('', 'l')).$2),
  ];
  final title = report.printTitle ?? report.title.toUpperCase();
  final form = StdForm(
    h1: title,
    h2: (s['entity'] ?? '').toUpperCase(),
    lines: [period],
    fund: 'Fund Cluster : ${(s['fundCluster'] ?? '').toUpperCase()}',
    columns: columns,
    rows: [for (final r in cells) [for (final v in r) v.$1]],
  );
  final signers = [for (final c in report.certification) StdSigner(c.label, c.caption)];
  return printPdf(title, (fonts) => buildStandardPdf(title, [form], signers, fonts));
}

Future<void> exportReportExcel(ReportDefinition report, List<ReportRow> rows) => exportTable(
      report.title,
      [for (final h in report.headers) h.label],
      [for (final r in rows) [for (final h in report.headers) h.raw(r)]],
    );

// ── The reports ──────────────────────────────────────────────────────────────

List<ReportDefinition> buildReportDefinitions() => [
      ReportDefinition(
        id: 'rpcppe',
        title: 'RPCPPE (Physical Count)',
        description: "Report on the Physical Count of Property, Plant and Equipment: one form per type of PPE, in the GSO's printed format.",
        icon: Icons.fact_check_outlined,
        load: () => _fetch('/assets'),
        // The report header (as-at date, fund cluster, accountable officer) is filled in above the list.
        hasRpcppeSettings: true,
        pick: PickConfig(
          toItems: rpcppeGroupsOf,
          noun: ('type of PPE', 'types of PPE'),
          placeholder: 'Search type, article, office, property No.',
          hint: 'Tick one or more types of PPE to export their physical count reports.',
          none: 'No assets on hand as at this date.',
          search: (g, q) =>
              str(g['categoryName']).toLowerCase().contains(q) ||
              g.rows.any((a) => [at(a, 'article.articleName'), at(a, 'office.officeName'), a['propertyNumber'], a['description']]
                  .any((v) => str(v).toLowerCase().contains(q))),
          label: (g) => str(g['categoryName']),
          columns: [
            PickColumn('Type of PPE', (g) => str(g['categoryName'])),
            PickColumn('Items', (g) => '${g.rows.length}', right: true),
            PickColumn('Total Value', (g) => rMoney(g['total']), right: true),
          ],
          expandLabel: 'items',
          expandedHeaders: _rpcppeHeaders,
          expandedRows: (g) => g.rows,
          summary: (items) =>
              '${items.fold<int>(0, (n, g) => n + g.rows.length)} items · Total ${rMoney(items.fold<num>(0, (n, g) => n + toNum(g['total'])))}',
          exportExcel: exportRpcppeExcel,
          exportPdf: printRpcppe,
        ),
      ),
      ReportDefinition(
        id: 'condition',
        title: 'Condition Report',
        printTitle: 'REPORT ON THE CONDITION OF PROPERTY, PLANT AND EQUIPMENT',
        description: 'Asset breakdown by condition: new, good, serviceable, repairable, and unserviceable counts.',
        icon: Icons.pie_chart_outline_rounded,
        load: () => _fetch('/assets'),
        // Aggregation runs after the date filter, on the assets inside the acquisition date range.
        dateField: 'acquisitionDate',
        aggregated: true,
        transform: (assets) {
          final map = <String, Map<String, dynamic>>{};
          for (final a in assets) {
            final key = str(a['condition']).isEmpty ? 'UNKNOWN' : str(a['condition']);
            final m = map.putIfAbsent(key, () => {'condition': key, 'count': 0, 'totalValue': 0.0, 'offices': <String>{}});
            m['count'] = (m['count'] as int) + 1;
            m['totalValue'] = (m['totalValue'] as num) + _lineAmount(a);
            final office = str(at(a, 'office.officeName'));
            if (office.isNotEmpty) (m['offices'] as Set<String>).add(office);
          }
          final rows = map.values.toList()..sort((a, b) => (b['count'] as int).compareTo(a['count'] as int));
          return [
            for (final r in rows)
              {...r, 'offices': (r['offices'] as Set<String>).isEmpty ? 'N/A' : (r['offices'] as Set<String>).join(', ')},
          ];
        },
        headers: [
          ReportColumn('Condition', display: (r) => str(r['condition']), raw: (r) => r['condition']),
          ReportColumn('Count', display: (r) => str(r['count']), raw: (r) => r['count']),
          ReportColumn('Total Value (₱)',
              display: (r) => toNum(r['totalValue']) > 0 ? rMoney(r['totalValue']) : 'N/A',
              raw: (r) => toNum(r['totalValue']) > 0 ? toNum(r['totalValue']).toStringAsFixed(2) : ''),
          ReportColumn('Offices', display: (r) => str(r['offices']), raw: (r) => r['offices']),
        ],
        certification: const [
          Signer('Prepared by:', 'Signature over Printed Name of Property Custodian / GSO Staff'),
          Signer('Approved by:', 'Signature over Printed Name of Municipal General Services Officer'),
        ],
      ),
      ReportDefinition(
        id: 'replacement',
        title: 'Replacement Forecast',
        printTitle: 'REPLACEMENT FORECAST OF PROPERTY, PLANT AND EQUIPMENT',
        description: 'Assets due for replacement now and in the next 3 years, with the estimated cost, for budget planning.',
        icon: Icons.event_repeat_outlined,
        // Same settings as Home's Budget & Planning, so the totals match it.
        load: () => _fetchItems('/ai-insights/replacement-forecast', {'years': 3}),
        dateField: 'endOfLife',
        headers: [
          ReportColumn('Replace In',
              display: (r) => r['replaceIn'] == 'NOW' ? 'Now' : str(r['replaceIn']),
              raw: (r) => r['replaceIn'] == 'NOW' ? 'Now' : str(r['replaceIn'])),
          ReportColumn('Property No.', display: (r) => _orNa(r['propertyNumber']), raw: (r) => str(r['propertyNumber'])),
          ReportColumn('Description', display: (r) => _orNa(r['description']), raw: (r) => str(r['description'])),
          ReportColumn('Category', display: (r) => _orNa(r['category']), raw: (r) => str(r['category'])),
          ReportColumn('Office', display: (r) => _orNa(r['office']), raw: (r) => str(r['office'])),
          ReportColumn('Acq. Date', display: (r) => rDate(r['acquisitionDate']), raw: (r) => str(r['acquisitionDate'])),
          ReportColumn('Expected Life',
              display: (r) => r['usefulLifeYears'] != null ? '${r['usefulLifeYears']} yrs' : 'N/A',
              raw: (r) => str(r['usefulLifeYears'])),
          ReportColumn('End of Life', display: (r) => rDate(r['endOfLife']), raw: (r) => str(r['endOfLife'])),
          ReportColumn('Reason', display: (r) => _orNa(r['reason']), raw: (r) => str(r['reason'])),
          ReportColumn('Condition', display: (r) => _orNa(r['condition']), raw: (r) => str(r['condition'])),
          ReportColumn('Acq. Value', display: (r) => rMoney(r['unitValue']), raw: (r) => _fixed(r['unitValue'])),
          ReportColumn('Est. Cost', display: (r) => rMoney(r['estimatedCost']), raw: (r) => _fixed(r['estimatedCost'])),
        ],
        certification: const [
          Signer('Prepared by:', 'Signature over Printed Name of Property Custodian / GSO Staff'),
          Signer('Approved by:', 'Signature over Printed Name of Municipal General Services Officer'),
        ],
      ),
      ReportDefinition(
        id: 'depreciation',
        title: 'Depreciation Schedule',
        printTitle: 'SCHEDULE OF DEPRECIATION OF PROPERTY, PLANT AND EQUIPMENT',
        description: 'Straight-line depreciation of assets in use as of today: residual value, monthly depreciation, accumulated depreciation and book value.',
        icon: Icons.trending_down_rounded,
        load: () => _fetchItems('/ai-insights/depreciation', const {}),
        dateField: 'acquisitionDate',
        headers: [
          ReportColumn('Property No.', display: (r) => _orNa(r['propertyNumber']), raw: (r) => str(r['propertyNumber'])),
          ReportColumn('Description', display: (r) => _orNa(r['description']), raw: (r) => str(r['description'])),
          ReportColumn('Category', display: (r) => _orNa(r['category']), raw: (r) => str(r['category'])),
          ReportColumn('Acquisition Date', display: (r) => rDate(r['acquisitionDate']), raw: (r) => str(r['acquisitionDate'])),
          ReportColumn('Total Cost', display: (r) => rMoney(r['totalCost']), raw: (r) => _fixed(r['totalCost'])),
          ReportColumn('Residual Value', display: (r) => rMoney(r['residualValue']), raw: (r) => _fixed(r['residualValue'])),
          ReportColumn('Depreciable Cost', display: (r) => rMoney(r['depreciableCost']), raw: (r) => _fixed(r['depreciableCost'])),
          ReportColumn('Useful Life (months)', display: (r) => str(r['usefulLifeMonths']), raw: (r) => r['usefulLifeMonths']),
          ReportColumn('Remaining Useful Life', display: (r) => str(r['remainingLifeMonths']), raw: (r) => r['remainingLifeMonths']),
          ReportColumn('Monthly Depreciation',
              display: (r) => r['monthlyDepreciation'] != null ? rMoney(r['monthlyDepreciation']) : '-',
              raw: (r) => r['monthlyDepreciation'] != null ? _fixed(r['monthlyDepreciation']) : '-'),
          ReportColumn('Depreciation Expense',
              display: (r) => toNum(r['depreciationExpense']) != 0 ? rMoney(r['depreciationExpense']) : '-',
              raw: (r) => toNum(r['depreciationExpense']) != 0 ? _fixed(r['depreciationExpense']) : '-'),
          ReportColumn('Accumulated Depreciation',
              display: (r) => rMoney(r['accumulatedDepreciation']), raw: (r) => _fixed(r['accumulatedDepreciation'])),
          ReportColumn('Book Value', display: (r) => rMoney(r['bookValue']), raw: (r) => _fixed(r['bookValue'])),
        ],
        certification: const [
          Signer('Prepared by:', 'Signature over Printed Name of Property Custodian / GSO Staff'),
          Signer('Certified Correct by:', 'Signature over Printed Name of Municipal Accountant'),
        ],
      ),
      // Medium and high risk assets from the machine-learning model (RepairRiskService), highest first.
      ReportDefinition(
        id: 'repairrisk',
        title: 'AI Repair Forecast',
        printTitle: 'AI FORECAST OF ASSETS LIKELY TO NEED REPAIR OR MAINTENANCE IN THE NEXT 12 MONTHS',
        description: 'Assets the AI expects to need repair in the next 12 months, learned from past repair '
            'records, with the reasons and what to do. Check the ones at the top first.',
        icon: Icons.warning_amber_rounded,
        load: () async {
          final res = await ApiClient.instance.dio.get('/ai-insights/repair-risk', queryParameters: {'items': true});
          return [for (final r in ((res.data as Map)['items'] as List? ?? const [])) Map<String, dynamic>.from(r as Map)];
        },
        headers: [
          ReportColumn('Chance', display: (r) => '${r['chancePercent']}%', raw: (r) => '${r['chancePercent']}%'),
          ReportColumn('Risk',
              display: (r) => r['level'] == 'HIGH' ? 'High' : 'Medium', raw: (r) => r['level'] == 'HIGH' ? 'High' : 'Medium'),
          ReportColumn('Recommended Action', display: (r) => _orNa(r['action']), raw: (r) => str(r['action'])),
          ReportColumn('Property No.', display: (r) => _orNa(r['propertyNumber']), raw: (r) => str(r['propertyNumber'])),
          ReportColumn('Description', display: (r) => _orNa(r['description']), raw: (r) => str(r['description'])),
          ReportColumn('Category', display: (r) => _orNa(r['category']), raw: (r) => str(r['category'])),
          ReportColumn('Office', display: (r) => _orNa(r['office']), raw: (r) => str(r['office'])),
          ReportColumn('Age', display: (r) => '${r['ageYears']} yrs', raw: (r) => r['ageYears']),
          ReportColumn('Why',
              display: (r) => _orNa(((r['reasons'] as List?) ?? const []).join('; ')),
              raw: (r) => ((r['reasons'] as List?) ?? const []).join('; ')),
        ],
        certification: const [
          Signer('Prepared by:', 'Signature over Printed Name of Property Custodian / GSO Staff'),
          Signer('Approved by:', 'Signature over Printed Name of Municipal General Services Officer'),
        ],
      ),
      // One row per type of property: the last 3 full years, this year so far, and next year's
      // estimate (MaintenanceForecastService), with a total row.
      ReportDefinition(
        id: 'maintenanceforecast',
        title: 'Repairs & Maintenance Forecast',
        printTitle: 'REPAIRS AND MAINTENANCE COST AND FORECAST',
        description: 'What repairs and maintenance cost in each of the last 3 years, by type of property, '
            'and about how much to budget for ${_forecastYear()}.',
        icon: Icons.build_circle_outlined,
        aggregated: true,
        load: () async {
          final res = await ApiClient.instance.dio.get('/ai-insights/maintenance-forecast');
          return [for (final r in (res.data as Map)['byCategory'] as List) Map<String, dynamic>.from(r as Map)];
        },
        transform: (rows) {
          if (rows.isEmpty) return rows;
          num sum(Object? Function(ReportRow) get) => rows.fold<num>(0, (s, r) => s + toNum(get(r)));
          return [
            ...rows,
            {
              'category': 'TOTAL',
              'perYear': {for (final y in _forecastHistory()) y: sum((r) => (r['perYear'] as Map?)?[y])},
              'average': sum((r) => r['average']),
              'forecast': sum((r) => r['forecast']),
              'trend': '',
            },
          ];
        },
        headers: [
          ReportColumn('Type of Property', display: (r) => str(r['category']), raw: (r) => str(r['category'])),
          for (final y in _forecastHistory())
            ReportColumn(y == '${_forecastYear() - 1}' ? '$y (so far)' : y,
                display: (r) => rMoney((r['perYear'] as Map?)?[y] ?? 0),
                raw: (r) => _fixed((r['perYear'] as Map?)?[y] ?? 0)),
          ReportColumn('3-Year Average', display: (r) => rMoney(r['average']), raw: (r) => _fixed(r['average'])),
          ReportColumn('Trend', display: (r) => _trendLabel[r['trend']] ?? '', raw: (r) => _trendLabel[r['trend']] ?? ''),
          ReportColumn('Estimate ${_forecastYear()}', display: (r) => rMoney(r['forecast']), raw: (r) => _fixed(r['forecast'])),
        ],
        certification: const [
          Signer('Prepared by:', 'Signature over Printed Name of Property Custodian / GSO Staff'),
          Signer('Approved by:', 'Signature over Printed Name of Municipal General Services Officer'),
        ],
      ),
      // Was the Maintenance Ledger; now the GSO's Repair and Maintenance Card, one per asset.
      ReportDefinition(
        id: 'maintenance',
        title: 'Repair and Maintenance Card',
        description: 'A card for each asset that has been repaired: every repair in date order, with its parts, labor and cost of repair.',
        icon: Icons.build_outlined,
        // the maintenance records carry the asset's number and name; the acquisition cost and
        // department come from the asset list
        load: () async {
          final both = await Future.wait([_fetch('/maintenance'), _fetch('/assets')]);
          return maintenanceCardsOf(both[0], both[1]);
        },
        pick: PickConfig(
          toItems: (cards, _) => [for (final c in cards) PickItem(str(c['assetId']), c)],
          noun: ('maintenance card', 'maintenance cards'),
          placeholder: 'Search property No., asset, department, repair',
          hint: 'Tick one or more assets to export their repair and maintenance cards.',
          none: 'No approved maintenance records yet, so there are no cards.',
          search: (c, q) => [
            c['propertyNumber'], c['description'], c['department'],
            for (final r in c['records'] as List) (r as Map)['actionsTaken'],
            for (final r in c['records'] as List) for (final i in ((r as Map)['items'] as List? ?? const [])) (i as Map)['particular'],
          ].any((v) => str(v).toLowerCase().contains(q)),
          label: (c) => 'maintenance card ${c['propertyNumber']}',
          columns: [
            PickColumn('Property No.', (c) => str(c['propertyNumber'])),
            PickColumn('Machine / Equipment', (c) => _orNa(c['description'])),
            PickColumn('Department', (c) => _orNa(c['department'])),
            PickColumn('Repairs', (c) => str(c['repairs']), right: true),
            PickColumn('Cost of Repairs', (c) => rMoney(c['totalCost']), right: true),
            PickColumn('Last Repair', (c) => rDate(c['lastRepair'])),
          ],
          expandLabel: 'card lines',
          expandedHeaders: maintenanceCardHeaders,
          expandedRows: (c) => maintenanceCardLines(c['records'] as List? ?? const []),
          summary: (items) =>
              '${items.fold<num>(0, (n, c) => n + toNum(c['repairs']))} repairs · Cost of repairs ${rMoney(items.fold<num>(0, (n, c) => n + toNum(c['totalCost'])))}',
          exportExcel: (items, _) => exportMaintenanceCardsExcel(items),
          exportPdf: (items, _) => printMaintenanceCards(items),
        ),
      ),
      ReportDefinition(
        id: 'par',
        title: 'PAR (Property Acknowledgment Receipt)',
        description: 'Select one or more PAR numbers to print their receipts, with the accountable person and total amount.',
        icon: Icons.assignment_turned_in_outlined,
        load: () => _fetch('/assets'),
        // No date filter: the list holds PAR numbers, and the ticked ones are exported.
        pick: PickConfig(
          toItems: (data, _) => parGroupsOf(data),
          noun: ('PAR number', 'PAR numbers'),
          placeholder: 'Search PAR, office, person, property No.',
          hint: 'Tick one or more PAR numbers to export their receipts.',
          none: 'No assets have a PAR number yet.',
          search: (g, q) =>
              str(g['par']).toLowerCase().contains(q) ||
              str(g['office']).toLowerCase().contains(q) ||
              str(g['receivedBy']).toLowerCase().contains(q) ||
              g.rows.any((r) => str(r['propertyNumber']).toLowerCase().contains(q)),
          label: (g) => 'PAR No. ${g['par']}',
          columns: [
            PickColumn('PAR No.', (g) => str(g['par'])),
            PickColumn('Office', (g) => _orNa(g['office'])),
            PickColumn('Accountable Person', (g) => _orNa(g['receivedBy'])),
            PickColumn('Items', (g) => '${g.rows.length}', right: true),
            PickColumn('Total Amount', (g) => rMoney(g['total']), right: true),
          ],
          expandLabel: 'items',
          expandedHeaders: _parHeaders,
          expandedRows: (g) => g.rows,
          summary: (items) =>
              '${items.fold<int>(0, (n, g) => n + g.rows.length)} items · Total ${rMoney(items.fold<num>(0, (n, g) => n + toNum(g['total'])))}',
          exportExcel: (items, _) => exportParExcel(items),
          exportPdf: (items, _) => printPar(items),
        ),
      ),
      ReportDefinition(
        id: 'propertycard',
        title: 'Property Card',
        description: 'A card for each transferred asset: who it was transferred to and which office, in date order.',
        icon: Icons.swap_horiz_rounded,
        load: () => _fetch('/property-cards', paged: false),
        // Only assets that have been transferred have a card; the backend leaves the rest out.
        pick: PickConfig(
          toItems: (cards, _) => [for (final c in cards) PickItem(str(c['assetId']), c)],
          noun: ('property card', 'property cards'),
          placeholder: 'Search property No., office, person',
          hint: 'Tick one or more assets to export their property cards.',
          none: 'No asset has been transferred yet, so there are no property cards.',
          search: (c, q) => [
            c['propertyNumber'], c['parNumber'], c['description'], c['currentOffice'], c['currentAccountable'],
            for (final e in _entries(c)) e['transferTo'],
            for (final e in _entries(c)) e['office'],
          ].any((v) => str(v).toLowerCase().contains(q)),
          label: (c) => 'property card ${c['propertyNumber']}',
          columns: [
            PickColumn('Property No.', (c) => str(c['propertyNumber'])),
            PickColumn('Description', (c) => _orNa(c['description'])),
            PickColumn('Current Office', (c) => _orNa(c['currentOffice'])),
            PickColumn('Accountable Person', (c) => _orNa(c['currentAccountable'])),
            PickColumn('Transfers', (c) => str(c['transferCount']), right: true),
            PickColumn('Last Transfer', (c) => rDate(c['lastTransferDate'])),
          ],
          expandLabel: 'card lines',
          expandedHeaders: _cardEntryHeaders,
          expandedRows: (c) => [for (final e in _entries(c)) Map<String, dynamic>.from(e)],
          summary: (items) => '${items.fold<num>(0, (n, c) => n + toNum(c['transferCount']))} transfers',
          exportExcel: (items, _) => exportPropertyCardsExcel(items),
          exportPdf: (items, _) => printPropertyCards(items),
        ),
      ),
      ReportDefinition(
        id: 'iirup',
        title: 'IIRUP (Unserviceable Property)',
        printTitle: 'INVENTORY AND INSPECTION REPORT OF UNSERVICEABLE PROPERTY',
        description: 'COA-format Inventory and Inspection Report of Unserviceable Property, for items pending disposal.',
        icon: Icons.delete_forever_outlined,
        load: () => _fetch('/disposal'),
        dateField: 'inspectionDate',
        headers: [
          ReportColumn('Date Acquired', printWidth: 6.5, display: (r) => rDate(at(r, 'asset.acquisitionDate')), raw: (r) => str(at(r, 'asset.acquisitionDate'))),
          ReportColumn('Particulars/Article', printWidth: 12, display: (r) => _orNa(at(r, 'asset.description')), raw: (r) => str(at(r, 'asset.description'))),
          ReportColumn('Property No.', printWidth: 9.5, display: (r) => _orNa(at(r, 'asset.propertyNumber')), raw: (r) => str(at(r, 'asset.propertyNumber'))),
          ReportColumn('PAR No.', printWidth: 8, display: (r) => _orNa(at(r, 'asset.parNumber')), raw: (r) => str(at(r, 'asset.parNumber'))),
          ReportColumn('Qty.', printWidth: 4, display: (r) => str(at(r, 'asset.quantity') ?? 1), raw: (r) => at(r, 'asset.quantity') ?? 1),
          ReportColumn('Unit Cost', printWidth: 7, display: (r) => rMoney(at(r, 'asset.unitValue')), raw: (r) => _fixed(at(r, 'asset.unitValue'))),
          ReportColumn('Total Cost', printWidth: 7,
              display: (r) => rMoney(_lineAmount(_assetOf(r))),
              raw: (r) => _lineAmount(_assetOf(r)).toStringAsFixed(2)),
          ReportColumn('Remarks', printWidth: 10, display: (r) => _orNa(r['inspectionFindings']), raw: (r) => str(r['inspectionFindings'])),
          for (final (label, method, width) in [('Sale', 'SALE', 4.0), ('Transfer', 'TRANSFER', 6.5), ('Destruction', 'DESTRUCTION', 8.5), ('Others (Specify)', 'OTHERS', 6.0)])
            ReportColumn(label, printWidth: width,
                display: (r) => r['recommendedMethod'] == method ? str(at(r, 'asset.quantity') ?? 1) : 'N/A',
                raw: (r) => r['recommendedMethod'] == method ? (at(r, 'asset.quantity') ?? 1) : ''),
          ReportColumn('Total', printWidth: 5, display: (r) => str(at(r, 'asset.quantity') ?? 1), raw: (r) => at(r, 'asset.quantity') ?? 1),
          ReportColumn('Appraised Value', printWidth: 6.5, display: (r) => rMoney(r['appraisedValue']), raw: (r) => _fixed(r['appraisedValue'])),
          ReportColumn('OR No.', printWidth: 5, display: (r) => _orNa(r['orNumber']), raw: (r) => str(r['orNumber'])),
          ReportColumn('Amount', printWidth: 6.5, display: (r) => rMoney(r['amount']), raw: (r) => _fixed(r['amount'])),
        ],
        certification: const [
          Signer('Inspected by:', 'Signature over Printed Name of GSO Inspector'),
          Signer('Certified Correct by:', 'Signature over Printed Name of Inventory Committee Chairman'),
          Signer('Recommending Approval:', 'Signature over Printed Name of Head of Office'),
          Signer('Approved by:', 'Signature over Printed Name of Local Chief Executive (Municipal Mayor)'),
        ],
      ),
    ];

ReportRow _assetOf(ReportRow r) => r['asset'] is Map ? Map<String, dynamic>.from(r['asset'] as Map) : const {};
