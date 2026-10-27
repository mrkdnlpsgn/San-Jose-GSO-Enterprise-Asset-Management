import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api/api_client.dart';
import '../../core/api/api_exception.dart';
import '../../core/connectivity/connectivity_provider.dart';
import '../../core/offline/asset_snapshot.dart';
import '../../core/offline/outbox.dart';
import '../../core/offline/response_cache.dart';
import '../../shared/data/reference_service.dart';
import '../asset_history/provider/asset_history_provider.dart';
import '../assets/data/asset_service.dart';
import '../assets/provider/asset_provider.dart';
import '../auth/provider/auth_provider.dart';
import '../dashboard/provider/dashboard_provider.dart';
import '../disposal/provider/disposal_provider.dart';
import '../maintenance/provider/maintenance_provider.dart';
import '../qr_scanner/provider/qr_lookup_provider.dart';
import '../transfer/provider/transfer_provider.dart';

/// The outbox, rebuilt whenever an item is added, changed or removed.
final outboxProvider = ChangeNotifierProvider<Outbox>((ref) => Outbox.instance);

class SyncState {
  final bool syncing;
  final int done;
  final int total;
  const SyncState({this.syncing = false, this.done = 0, this.total = 0});
}

/// Uploads the outbox, oldest first, whenever the phone is online and someone is signed in:
/// on reconnect, at sign-in, right after something is saved offline, and every minute while
/// anything is still waiting (the server may have been asleep). Also keeps the offline asset
/// list fresh.
///
/// An item the server can't take as-is (changed on the server
/// meanwhile, refused) is set aside for the user, and anything else for the same record
/// waits behind it - everything unrelated still goes.
final syncEngineProvider = NotifierProvider<SyncEngine, SyncState>(SyncEngine.new);

enum _Result { ok, setAside, stop }

class SyncEngine extends Notifier<SyncState> {
  Timer? _timer;
  bool _running = false;
  DateTime? _copyRefreshedAt;

  @override
  SyncState build() {
    ref.listen<AsyncValue<bool>>(isOnlineProvider, (prev, next) {
      final online = next.valueOrNull;
      if (online == null) return;
      ApiClient.instance.deviceOffline = !online;
      if (online && prev?.valueOrNull == false) _soon(const Duration(seconds: 2));
    }, fireImmediately: true);
    ref.listen(authProvider, (prev, next) {
      final user = next.valueOrNull;
      if (user != null && prev?.valueOrNull?.username != user.username) {
        _soon(const Duration(seconds: 1), signedIn: true);
      }
    }, fireImmediately: true);
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (Outbox.instance.items.any((i) => i.status == OutboxStatus.pending)) sync();
      _refreshCopyIfStale();
    });
    ref.onDispose(() => _timer?.cancel());
    return const SyncState();
  }

  void _soon(Duration delay, {bool signedIn = false}) {
    Timer(delay, () async {
      if (signedIn) {
        unawaited(ResponseCacheInterceptor.prune());
        await _refreshCopy();
      }
      await sync();
    });
  }

  /// Called after something is saved to the outbox - uploads it right away if possible.
  void poke() => _soon(const Duration(milliseconds: 300));

  bool get _canSync => !ApiClient.instance.deviceOffline && ref.read(authProvider).valueOrNull != null;

  Future<void> _refreshCopyIfStale() async {
    final at = _copyRefreshedAt;
    if (at == null || DateTime.now().difference(at) > const Duration(minutes: 15)) await _refreshCopy();
  }

  // The full asset list plus the pick lists forms need, so they all work offline.
  Future<void> _refreshCopy() async {
    if (!_canSync) return;
    try {
      await AssetService().refreshOfflineCopy();
      final refs = ReferenceService();
      await Future.wait([refs.getCategories(), refs.getOffices(), refs.getPersonnel()]);
      _copyRefreshedAt = DateTime.now();
    } catch (_) {
      // try again on the next tick
    }
  }

  /// Uploads waiting items. With [onlyId], retries that one item whatever its status
  /// (after the user entered a code, chose "keep mine", or fixed a refused item).
  Future<void> sync({String? onlyId}) async {
    if (_running || !_canSync) return;
    _running = true;
    var changed = false;
    try {
      final all = Outbox.instance.items;
      // records with an item set aside: later items for them wait
      final blocked = {
        for (final i in all)
          if (i.needsAttention && i.id != onlyId) _recordPath(i)
      }..remove(null);
      final queue = all.where((i) => onlyId != null ? i.id == onlyId : i.status == OutboxStatus.pending).toList();
      if (queue.isEmpty) return;
      state = SyncState(syncing: true, total: queue.length);
      var done = 0;
      for (final item in queue) {
        if (Outbox.instance.byId(item.id) == null) continue; // discarded meanwhile
        final path = _recordPath(item);
        if (_waitsOnUnsentRecord(item) || blocked.contains(path)) continue;
        final result = await _send(item);
        if (result == _Result.stop) break;
        if (result == _Result.ok) {
          changed = true;
        } else if (path != null) {
          blocked.add(path);
        }
        state = SyncState(syncing: true, done: ++done, total: queue.length);
      }
    } finally {
      _running = false;
      state = const SyncState();
      if (changed) {
        _refreshScreens();
        unawaited(_refreshCopy());
      }
    }
  }

  // The record an item belongs to (null for a brand-new record with nothing before it).
  static String? _recordPath(OutboxItem i) {
    if (i.isPhoto) return i.path.replaceFirst(RegExp(r'/(photos|evidence)$'), '');
    if (i.isCreate) return null;
    return i.path;
  }

  // Still points at something created offline that hasn't uploaded yet.
  static bool _waitsOnUnsentRecord(OutboxItem i) {
    if (RegExp(r'/-\d+(/|$)').hasMatch(i.path)) return true;
    final b = i.body;
    return b != null && b.entries.any((e) => e.key.endsWith('Id') && e.value is int && (e.value as int) < 0);
  }

  Future<_Result> _send(OutboxItem item) async {
    final dio = ApiClient.instance.dio;
    final outbox = Outbox.instance;
    try {
      // An edit: has anyone else changed the record since it was opened on this phone?
      final base = item.baseUpdatedAt;
      if (item.method == 'PUT' && base != null && base.isNotEmpty && item.status != OutboxStatus.conflict) {
        final current = await dio.get(item.path, options: Options(extra: {'noCache': true}));
        final server = (current.data as Map).cast<String, dynamic>();
        if ('${server['updatedAt'] ?? ''}' != base) {
          item
            ..status = OutboxStatus.conflict
            ..serverCopy = server
            ..error = 'Someone changed this record on the server after you opened it.';
          await outbox.update(item);
          return _Result.setAside;
        }
      }

      Object? data = item.body;
      if (item.isPhoto) {
        final f = item.filePath;
        if (f == null || !await File(f).exists()) {
          item
            ..status = OutboxStatus.failed
            ..error = 'The photo is no longer on this phone.';
          await outbox.update(item);
          return _Result.setAside;
        }
        data = FormData.fromMap({'file': await MultipartFile.fromFile(f, filename: item.fileName)});
      }

      final res = await dio.request<dynamic>(
        item.path,
        data: data,
        options: Options(
          method: item.method,
          headers: {if (item.idempotencyKey != null) 'Idempotency-Key': item.idempotencyKey},
          extra: {'noCache': true},
        ),
      );

      final saved = res.data is Map ? (res.data as Map).cast<String, dynamic>() : null;
      final tempId = item.tempId;
      final realId = saved?['id'];
      if (tempId != null && realId is int) await outbox.resolveTempId(tempId, realId);
      if (item.kind.startsWith('asset.') && saved != null && saved['propertyNumber'] != null) {
        await AssetSnapshot.instance.upsert(saved);
      }
      await outbox.remove(item);
      return _Result.ok;
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      // offline, timed out, server asleep or restarting - try again later
      if (e.response == null || const [502, 503, 504].contains(status)) return _Result.stop;
      // signed out (the session-expiry handler takes the user to sign-in) - resume after
      if (status == 401 || ref.read(authProvider).valueOrNull == null) return _Result.stop;
      item
        ..status = OutboxStatus.failed
        ..error = ApiException.from(e).message;
      await outbox.update(item);
      return _Result.setAside;
    }
  }

  void _refreshScreens() {
    ref.invalidate(assetsPagedProvider);
    ref.invalidate(assetCountProvider);
    ref.invalidate(assetDetailProvider);
    ref.invalidate(qrLookupAssetsProvider);
    ref.invalidate(assetHistoryProvider);
    ref.invalidate(maintenancePagedProvider);
    ref.invalidate(maintenanceCountProvider);
    ref.invalidate(maintenanceDetailProvider);
    ref.invalidate(maintenanceByAssetProvider);
    ref.invalidate(disposalPagedProvider);
    ref.invalidate(disposalCountProvider);
    ref.invalidate(disposalDetailProvider);
    ref.invalidate(disposalByAssetProvider);
    ref.invalidate(transfersProvider);
    ref.invalidate(dashboardStatsProvider);
  }

  // ── actions from the Outbox screen ─────────────────────────────────────────

  /// Sends a set-aside item again (after the user dealt with it).
  Future<void> retry(OutboxItem item) async {
    item
      ..status = OutboxStatus.pending
      ..error = null;
    await Outbox.instance.update(item);
    await sync(onlyId: item.id);
    if (Outbox.instance.byId(item.id) != null) return;
    await sync(); // it went through - anything waiting behind it can go too
  }

  /// Conflict: overwrite the server's version with this phone's.
  Future<void> keepMine(OutboxItem item) async {
    item.serverCopy = null;
    item.status = OutboxStatus.conflict; // tells _send to skip the check this once
    await Outbox.instance.update(item);
    await sync(onlyId: item.id);
    if (Outbox.instance.byId(item.id) == null) await sync();
  }

  Future<void> discard(OutboxItem item) async {
    await Outbox.instance.remove(item);
    _refreshScreens();
  }
}

/// Saves now when the server can be reached; otherwise puts the change in the outbox and
/// returns null. [forceQueue] for edits to something that only exists on this phone so far.
Future<T?> sendOrQueue<T>(
  WidgetRef ref, {
  required Future<T> Function() send,
  required Future<void> Function() queue,
  bool forceQueue = false,
}) async {
  Future<T?> queued() async {
    await queue();
    ref.read(syncEngineProvider.notifier).poke();
    return null;
  }

  if (forceQueue || ApiClient.instance.deviceOffline) return queued();
  try {
    return await send();
  } on ApiException catch (e) {
    if (!e.serverAsleep) rethrow;
    return queued();
  }
}

/// The confirmation shown after a change was kept on the phone.
void showSavedOffline(BuildContext context, {String what = 'Saved'}) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text("$what on this phone. It will upload when you're back online."),
    behavior: SnackBarBehavior.floating,
  ));
}
