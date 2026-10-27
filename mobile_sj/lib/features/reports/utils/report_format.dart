// Formatting for the Reports, matching the web Reports page (en-PH dates, ₱ amounts).

const _short = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const _long = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September',
  'October', 'November', 'December'];

/// The calendar date (yyyy-mm-dd) of an API date or timestamp, in Manila time.
String manilaDateKey(Object? value) {
  if (value == null) return '';
  final s = value.toString();
  if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s)) return s;
  final d = DateTime.tryParse(s);
  if (d == null) return s.length >= 10 ? s.substring(0, 10) : s;
  final m = (d.isUtc ? d : d.toUtc()).add(const Duration(hours: 8));
  return dateKey(m);
}

String dateKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String todayKey() => manilaDateKey(DateTime.now().toUtc().toIso8601String());

DateTime? _parse(Object? v) {
  if (v == null || v.toString().isEmpty) return null;
  final key = manilaDateKey(v);
  return DateTime.tryParse(key);
}

/// "Oct 27, 2026", or N/A.
String rDate(Object? v) {
  final d = _parse(v);
  return d == null ? 'N/A' : '${_short[d.month - 1]} ${d.day}, ${d.year}';
}

/// "October 27, 2026", or empty.
String longDate(Object? v) {
  final d = _parse(v);
  return d == null ? '' : '${_long[d.month - 1]} ${d.day}, ${d.year}';
}

/// "1,234.50"
String money(num v) {
  final fixed = v.toStringAsFixed(2);
  final neg = fixed.startsWith('-');
  final parts = (neg ? fixed.substring(1) : fixed).split('.');
  final buf = StringBuffer();
  for (var i = 0; i < parts[0].length; i++) {
    if (i > 0 && (parts[0].length - i) % 3 == 0) buf.write(',');
    buf.write(parts[0][i]);
  }
  return '${neg ? '-' : ''}$buf.${parts[1]}';
}

/// "₱1,234.50", or N/A when blank.
String rMoney(Object? v) {
  if (v == null || v == '') return 'N/A';
  final n = v is num ? v : num.tryParse(v.toString());
  return n == null ? 'N/A' : '₱${money(n)}';
}

num toNum(Object? v, [num fallback = 0]) =>
    v is num ? v : (v == null ? fallback : num.tryParse(v.toString()) ?? fallback);

/// Reads a nested value: at(row, 'asset.office.officeName').
dynamic at(Map<String, dynamic>? row, String path) {
  dynamic cur = row;
  for (final k in path.split('.')) {
    if (cur is! Map) return null;
    cur = cur[k];
  }
  return cur;
}

String str(Object? v) => v == null ? '' : v.toString();

/// File and sheet names can't contain : \ / ? * [ ] - PAR numbers like 2026-09:GA21231 do.
String safeName(String s) => s.replaceAll(RegExp(r'[:\\/?*\[\]]'), '-');
