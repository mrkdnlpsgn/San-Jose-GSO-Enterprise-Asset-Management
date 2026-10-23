import 'package:flutter/material.dart';

/// A single exportable column: how to read a value out of a report row.
/// Rows are `dynamic` because a report's row type (AssetModel, DisposalModel,
/// MaintenanceModel, AssetHistoryModel, or a plain summary map) varies per report -
/// each ReportDefinition's own columns know how to cast their own rows.
class ReportColumn {
  final String label;
  final String Function(dynamic row) valueOf;

  const ReportColumn(this.label, this.valueOf);
}

class ReportDefinition {
  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final Future<List<dynamic>> Function() load;
  final List<ReportColumn> columns;

  /// COA-style signature roles, rendered as blank signature lines on the exported PDF.
  final List<String>? certification;

  /// Optional summary/total row(s) appended only at export time (not in the on-screen preview).
  final List<dynamic> Function(List<dynamic> rows)? extraRows;

  const ReportDefinition({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.load,
    required this.columns,
    this.certification,
    this.extraRows,
  });
}
