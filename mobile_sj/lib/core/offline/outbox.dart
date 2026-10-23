import 'dart:io';
import 'package:flutter/foundation.dart';
import '../../shared/utils/idempotency.dart';
import 'offline_store.dart';

/// Where an outbox item stands.
enum OutboxStatus {
  /// Waiting for a connection; uploads automatically.
  pending,

  /// The server emailed a code and the user hasn't entered it yet.
  needsCode,

  /// Someone changed the same record on the server since it was opened on this phone.
  conflict,

  /// The server refused it (e.g. a duplicate property number); needs the user.
  failed,
}

/// One change made on this phone that hasn't reached the server yet.
class OutboxItem {
  final String id;

  /// e.g. asset.create, asset.update, maintenance.create, disposal.update, transfer.create, photo.upload
  final String kind;
  final String method;

  /// API path; may hold a temporary (negative) id until the record it belongs to is uploaded.
  String path;
  Map<String, dynamic>? body;
  final String? idempotencyKey;

  /// The record's `updatedAt` when it was opened for editing - compared before uploading an edit.
  final String? baseUpdatedAt;

  /// For a create: the negative id it stands in for until the server gives the real one.
  final int? tempId;
  String label;
  final String createdAt;
  final String username;

  /// The record as it will look once uploaded (an asset's JSON), so lists can show it offline.
  Map<String, dynamic>? preview;

  /// A photo kept on the phone until it uploads.
  final String? filePath;
  final String? fileName;
  OutboxStatus status;
  String? error;

  /// The server's copy of the record when there is a [OutboxStatus.conflict].
  Map<String, dynamic>? serverCopy;

  OutboxItem({
    required this.id,
    required this.kind,
    required this.method,
    required this.path,
    this.body,
    this.idempotencyKey,
    this.baseUpdatedAt,
    this.tempId,
    required this.label,
    required this.createdAt,
    required this.username,
    this.preview,
    this.filePath,
    this.fileName,
    this.status = OutboxStatus.pending,
    this.error,
    this.serverCopy,
  });

  bool get isCreate => kind.endsWith('.create');
  bool get isPhoto => kind == 'photo.upload';
  bool get needsAttention => status != OutboxStatus.pending;

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind,
        'method': method,
        'path': path,
        'body': body,
        'idempotencyKey': idempotencyKey,
        'baseUpdatedAt': baseUpdatedAt,
        'tempId': tempId,
        'label': label,
        'createdAt': createdAt,
        'username': username,
        'preview': preview,
        'filePath': filePath,
        'fileName': fileName,
        'status': status.name,
        'error': error,
        'serverCopy': serverCopy,
      };

  factory OutboxItem.fromJson(Map<String, dynamic> j) => OutboxItem(
        id: j['id'] as String,
        kind: j['kind'] as String,
        method: j['method'] as String,
        path: j['path'] as String,
        body: (j['body'] as Map?)?.cast<String, dynamic>(),
        idempotencyKey: j['idempotencyKey'] as String?,
        baseUpdatedAt: j['baseUpdatedAt'] as String?,
        tempId: j['tempId'] as int?,
        label: j['label'] as String? ?? 'Change',
        createdAt: j['createdAt'] as String? ?? '',
        username: j['username'] as String? ?? '',
        preview: (j['preview'] as Map?)?.cast<String, dynamic>(),
        filePath: j['filePath'] as String?,
        fileName: j['fileName'] as String?,
        status: OutboxStatus.values.asNameMap()[j['status']] ?? OutboxStatus.pending,
        error: j['error'] as String?,
        serverCopy: (j['serverCopy'] as Map?)?.cast<String, dynamic>(),
      );
}

/// The changes waiting to upload, oldest first, saved to `<documents>/offline/outbox.json`.
/// Items carry the account that made them; only that account's items are shown or uploaded.
class Outbox extends ChangeNotifier {
  Outbox._();
  static final Outbox instance = Outbox._();

  final List<OutboxItem> _items = [];
  bool _loaded = false;

  File get _file => File('${OfflineStore.instance.rootDir.path}/outbox.json');

  Future<void> load() async {
    if (_loaded) return;
    final saved = await OfflineStore.readJson(_file);
    if (saved is List) {
      _items.addAll(saved.whereType<Map>().map((m) => OutboxItem.fromJson(m.cast<String, dynamic>())));
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> _save() async {
    await OfflineStore.writeJson(_file, _items.map((i) => i.toJson()).toList());
    notifyListeners();
  }

  /// The signed-in account's items, oldest first.
  List<OutboxItem> get items {
    final me = OfflineStore.instance.account;
    return List.unmodifiable(_items.where((i) => i.username == me));
  }

  OutboxItem? byId(String id) => _items.where((i) => i.id == id).firstOrNull;

  /// The next free temporary id (negative, so it can never clash with a real one).
  int nextTempId() {
    final lowest = _items.map((i) => i.tempId ?? 0).fold<int>(0, (a, b) => b < a ? b : a);
    return lowest - 1;
  }

  /// Saves a create or an edit. An edit to a record that is itself still waiting (created
  /// offline, or already edited offline) is folded into that item instead of queued again,
  /// so one record never has two competing uploads.
  Future<OutboxItem> add({
    required String kind,
    required String method,
    required String path,
    Map<String, dynamic>? body,
    String? baseUpdatedAt,
    required String label,
    Map<String, dynamic>? preview,
    String? idempotencyKey,
    String? filePath,
    String? fileName,
  }) async {
    final me = OfflineStore.instance.account ?? '';
    final entity = kind.split('.').first;

    if (kind.endsWith('.update')) {
      final id = int.tryParse(path.split('/').last);
      // edit of something created offline → change the create itself
      final create = _items.where((i) => i.username == me && i.kind == '$entity.create' && i.tempId == id).firstOrNull;
      if (create != null) {
        create.body = body;
        if (preview != null) create.preview = preview;
        create.label = label.replaceFirst('Edit', 'New');
        create.status = OutboxStatus.pending;
        create.error = null;
        await _save();
        return create;
      }
      // second edit of the same record → replace the first, keeping the original base
      final earlier = _items.where((i) => i.username == me && i.kind == kind && i.path == path).firstOrNull;
      if (earlier != null) {
        earlier.body = body;
        if (preview != null) earlier.preview = preview;
        earlier.label = label;
        earlier.status = OutboxStatus.pending;
        earlier.error = null;
        earlier.serverCopy = null;
        await _save();
        return earlier;
      }
    }

    final item = OutboxItem(
      id: newIdempotencyKey(),
      kind: kind,
      method: method,
      path: path,
      body: body,
      // a retried POST must not create the record twice - the server remembers this key
      idempotencyKey: method == 'POST' ? (idempotencyKey ?? newIdempotencyKey()) : null,
      baseUpdatedAt: baseUpdatedAt,
      tempId: kind.endsWith('.create') && !kind.startsWith('transfer') ? nextTempId() : null,
      label: label,
      createdAt: DateTime.now().toUtc().toIso8601String(),
      username: me,
      preview: preview,
      filePath: filePath,
      fileName: fileName,
    );
    if (item.tempId != null && item.preview != null) item.preview!['id'] = item.tempId;
    _items.add(item);
    await _save();
    return item;
  }

  Future<void> update(OutboxItem item) => _save();

  Future<void> remove(OutboxItem item) async {
    _items.remove(item);
    final f = item.filePath;
    if (f != null) {
      try {
        await File(f).delete();
      } catch (_) {}
    }
    await _save();
  }

  /// After a create uploads: point everything that used its temporary id at the real one.
  Future<void> resolveTempId(int tempId, int realId) async {
    final segment = RegExp('/${RegExp.escape('$tempId')}(?=/|\$)');
    for (final i in _items) {
      i.path = i.path.replaceAll(segment, '/$realId');
      final b = i.body;
      if (b != null) {
        for (final k in b.keys.toList()) {
          if (k.endsWith('Id') && b[k] == tempId) b[k] = realId;
        }
      }
      if (i.preview?['id'] == tempId) i.preview!['id'] = realId;
    }
    await _save();
  }

  /// Pending photos for one record's photo endpoint (e.g. /maintenance/5/photos).
  List<OutboxItem> photosFor(String path) => items.where((i) => i.isPhoto && i.path == path).toList();
}
