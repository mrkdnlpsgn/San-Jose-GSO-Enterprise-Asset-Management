import 'dart:io';
import '../../features/assets/model/asset_model.dart';
import 'offline_store.dart';
import 'outbox.dart';

/// Every asset the signed-in account can see (staff: their offices; admin: all), kept on the
/// phone so search, filters, detail and QR lookup still work offline. Refreshed whenever the
/// full list is downloaded online (the Scan tab does this too), and patched after each save.
///
/// Changes waiting in the outbox are laid over it: an asset added offline appears at the top,
/// an asset edited offline shows the edit.
class AssetSnapshot {
  AssetSnapshot._();
  static final AssetSnapshot instance = AssetSnapshot._();

  List<Map<String, dynamic>>? _rows;
  String? _rowsAccount;
  DateTime? savedAt;

  File? get _file {
    final dir = OfflineStore.instance.accountDir();
    return dir == null ? null : File('${dir.path}/assets.json');
  }

  Future<List<Map<String, dynamic>>?> _load() async {
    final account = OfflineStore.instance.account;
    if (_rows != null && _rowsAccount == account) return _rows;
    _rows = null;
    savedAt = null;
    final f = _file;
    if (f == null) return null;
    final saved = await OfflineStore.readJson(f);
    if (saved is Map && saved['rows'] is List) {
      _rows = (saved['rows'] as List).whereType<Map>().map((m) => m.cast<String, dynamic>()).toList();
      savedAt = DateTime.tryParse(saved['savedAt'] as String? ?? '');
      _rowsAccount = account;
    }
    return _rows;
  }

  Future<bool> get available async => (await _load()) != null;

  Future<void> _persist() async {
    final f = _file;
    if (f == null || _rows == null) return;
    try {
      await OfflineStore.writeJson(f, {'savedAt': savedAt?.toIso8601String(), 'rows': _rows});
    } catch (_) {}
  }

  /// Replaces the whole list with a fresh download.
  Future<void> replaceAll(List<dynamic> rows) async {
    _rows = rows.whereType<Map>().map((m) => m.cast<String, dynamic>()).toList();
    _rowsAccount = OfflineStore.instance.account;
    savedAt = DateTime.now().toUtc();
    await _persist();
  }

  /// Puts one asset as the server just returned it (after a save) into the list.
  Future<void> upsert(Map<String, dynamic> row) async {
    final rows = await _load();
    if (rows == null) return;
    final i = rows.indexWhere((r) => r['id'] == row['id']);
    if (i >= 0) {
      rows[i] = row;
    } else {
      rows.insert(0, row);
    }
    await _persist();
  }

  /// The list with waiting changes laid over it.
  Future<List<AssetModel>?> _merged() async {
    final rows = await _load();
    if (rows == null) return null;
    final byId = <int, Map<String, dynamic>>{for (final r in rows) r['id'] as int: r};
    final added = <Map<String, dynamic>>[];
    for (final item in Outbox.instance.items) {
      final p = item.preview;
      if (p == null || !item.kind.startsWith('asset.')) continue;
      final id = p['id'] as int?;
      if (id == null) continue;
      if (item.isCreate && !byId.containsKey(id)) {
        added.add(p);
      } else {
        byId[id] = p;
      }
    }
    final out = <AssetModel>[];
    for (final m in [...added.reversed, ...byId.values]) {
      try {
        out.add(AssetModel.fromJson(m));
      } catch (_) {
        // a row in an unexpected shape is skipped rather than breaking the whole list
      }
    }
    return out;
  }

  static bool _matches(AssetModel a, String q) {
    bool has(String? s) => s != null && s.toLowerCase().contains(q);
    return has(a.propertyNumber) ||
        has(a.parNumber) ||
        has(a.serialNumber) ||
        has(a.description) ||
        has(a.office.officeName) ||
        has(a.category.categoryName) ||
        has(a.accountablePerson?.fullName) ||
        has(a.location);
  }

  Future<List<AssetModel>?> _filtered({
    String? search,
    int? categoryId,
    int? officeId,
    String? condition,
    String? lifecycleStatus,
  }) async {
    final all = await _merged();
    if (all == null) return null;
    final q = search?.trim().toLowerCase() ?? '';
    return all.where((a) {
      if (q.isNotEmpty && !_matches(a, q)) return false;
      if (categoryId != null && a.category.id != categoryId) return false;
      if (officeId != null && a.office.id != officeId) return false;
      if (condition != null && condition.isNotEmpty && a.condition != condition) return false;
      if (lifecycleStatus != null && lifecycleStatus.isNotEmpty && a.lifecycleStatus != lifecycleStatus) return false;
      return true;
    }).toList();
  }

  /// Same parameters and paging as GET /assets. Null when nothing has been downloaded yet.
  Future<List<AssetModel>?> query({
    String? search,
    int page = 0,
    int size = 20,
    int? categoryId,
    int? officeId,
    String? condition,
    String? lifecycleStatus,
  }) async {
    final list = await _filtered(
        search: search,
        categoryId: categoryId,
        officeId: officeId,
        condition: condition,
        lifecycleStatus: lifecycleStatus);
    if (list == null) return null;
    final start = page * size;
    if (start >= list.length) return [];
    return list.sublist(start, (start + size).clamp(0, list.length));
  }

  Future<int?> count(
          {String? search, int? categoryId, int? officeId, String? condition, String? lifecycleStatus}) async =>
      (await _filtered(
              search: search,
              categoryId: categoryId,
              officeId: officeId,
              condition: condition,
              lifecycleStatus: lifecycleStatus))
          ?.length;

  Future<AssetModel?> byId(int id) async {
    final all = await _merged();
    return all?.where((a) => a.id == id).firstOrNull;
  }

  /// The raw saved JSON of one asset (before waiting changes), to build an offline edit on.
  Future<Map<String, dynamic>?> rawById(int id) async => (await _load())?.where((r) => r['id'] == id).firstOrNull;
}
