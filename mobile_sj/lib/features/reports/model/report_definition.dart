import 'package:flutter/material.dart';

/// One record as the API returns it (an asset, a maintenance or disposal record, a property
/// card...). Reports read the same JSON the web Reports page does, so both build the same
/// rows, filters and printouts.
typedef ReportRow = Map<String, dynamic>;

/// A column: [display] is what the screen shows, [raw] what goes into Excel and the printout.
class ReportColumn {
  final String label;
  final String Function(ReportRow row) display;
  final Object? Function(ReportRow row) raw;
  /// Relative column width on the printed form; columns without one share the rest equally.
  final double? printWidth;

  const ReportColumn(this.label, {required this.display, required this.raw, this.printWidth});
}

/// A signature line on a printed report.
class Signer {
  final String label;
  final String caption;
  const Signer(this.label, this.caption);
}

/// One pickable item of a pick-and-export report: a type of PPE, a PAR number, a property card.
class PickItem {
  final String key;
  final Map<String, dynamic> data;
  final List<ReportRow> rows;
  const PickItem(this.key, this.data, [this.rows = const []]);

  dynamic operator [](String k) => data[k];
}

class PickColumn {
  final String label;
  final String Function(PickItem item) cell;
  final bool right;
  const PickColumn(this.label, this.cell, {this.right = false});
}

/// Reports where the user ticks items and exports those (RPCPPE, PAR, Property Card).
class PickConfig {
  final List<PickItem> Function(List<ReportRow> data, Map<String, String> settings) toItems;
  final (String, String) noun;
  final String placeholder;
  final String hint;
  final String none;
  final bool Function(PickItem item, String q) search;
  final String Function(PickItem item) label;
  final List<PickColumn> columns;
  final String expandLabel;
  final List<ReportColumn> expandedHeaders;
  final List<ReportRow> Function(PickItem item) expandedRows;
  final String Function(List<PickItem> items) summary;
  final Future<void> Function(List<PickItem> items, Map<String, String> settings) exportExcel;
  final Future<void> Function(List<PickItem> items, Map<String, String> settings) exportPdf;

  const PickConfig({
    required this.toItems,
    required this.noun,
    required this.placeholder,
    required this.hint,
    required this.none,
    required this.search,
    required this.label,
    required this.columns,
    required this.expandLabel,
    required this.expandedHeaders,
    required this.expandedRows,
    required this.summary,
    required this.exportExcel,
    required this.exportPdf,
  });
}

class ReportDefinition {
  final String id;
  final String title;
  /// The heading of the printed report, when it differs from [title].
  final String? printTitle;
  final String description;
  final IconData icon;
  final Future<List<ReportRow>> Function() load;

  /// The date the From/To filter works on; null = no date filter.
  final String? dateField;
  /// Rows are summaries (the Condition Report), so the "(of N)" raw count isn't shown.
  final bool aggregated;
  final List<ReportRow> Function(List<ReportRow> rows)? transform;
  final List<ReportColumn> headers;
  final List<Signer> certification;

  /// The RPCPPE's report details (as at, fund cluster, accountable officer...).
  final bool hasRpcppeSettings;
  final PickConfig? pick;

  const ReportDefinition({
    required this.id,
    required this.title,
    this.printTitle,
    required this.description,
    required this.icon,
    required this.load,
    this.dateField,
    this.aggregated = false,
    this.transform,
    this.headers = const [],
    this.certification = const [],
    this.hasRpcppeSettings = false,
    this.pick,
  });
}
