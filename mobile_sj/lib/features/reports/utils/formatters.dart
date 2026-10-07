const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
];

/// Formats an ISO date/date-time string as e.g. "Jan 15, 2026". Falls back to the raw
/// string (or '—') if it isn't parseable — reports show partial data over a crash.
String fmtDate(String? iso) {
  if (iso == null || iso.isEmpty) return '—';
  final d = DateTime.tryParse(iso)?.toLocal();
  if (d == null) return iso;
  return '${_months[d.month - 1]} ${d.day}, ${d.year}';
}

String rawDate(String? iso) => iso ?? '';

/// Formats a number as PHP currency with thousands separators, e.g. "₱52,000.00".
String fmtMoney(num? v) {
  if (v == null) return '—';
  final fixed = v.toStringAsFixed(2);
  final parts = fixed.split('.');
  final intPart = parts[0];
  final buf = StringBuffer();
  for (int i = 0; i < intPart.length; i++) {
    if (i > 0 && (intPart.length - i) % 3 == 0) buf.write(',');
    buf.write(intPart[i]);
  }
  return '₱$buf.${parts[1]}';
}

String rawMoney(num? v) => v != null ? v.toStringAsFixed(2) : '';
