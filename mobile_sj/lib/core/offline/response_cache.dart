import 'dart:io';
import 'package:dio/dio.dart';
import 'offline_store.dart';

/// Keeps the last answer to every GET on the phone, and answers from it when the server
/// can't be reached — so any screen that was opened before shows what it showed last time.
///
/// While the phone has no network at all, nothing waits on a timeout: GETs are answered from
/// the saved copy (or fail at once), and every other request fails at once so a form can
/// save it to the outbox straight away.
class ResponseCacheInterceptor extends Interceptor {
  /// Set from the connectivity provider: true while the phone has no network interface up.
  bool deviceOffline = false;

  /// Requests that skip the cache: sign-in, live events, version checks, and anything a
  /// caller marks with `extra: {'noCache': true}` (e.g. the full asset download, stored separately).
  static bool _cacheable(RequestOptions o) {
    if (o.method.toUpperCase() != 'GET' || o.extra['noCache'] == true) return false;
    if (o.responseType == ResponseType.bytes || o.responseType == ResponseType.stream) return false;
    final p = o.path;
    return !(p.contains('/auth/') || p.contains('/events') || p.contains('/actuator') || p.contains('/app/version'));
  }

  static String _key(RequestOptions o) {
    final q = o.queryParameters.entries.where((e) => e.value != null).toList()..sort((a, b) => a.key.compareTo(b.key));
    return '${o.path}?${q.map((e) => '${e.key}=${e.value}').join('&')}';
  }

  static File? _fileFor(RequestOptions o) {
    final dir = OfflineStore.instance.accountDir('cache');
    return dir == null ? null : File('${dir.path}/${OfflineStore.fnv1a(_key(o))}.json');
  }

  static DioException _offline(RequestOptions o) => DioException(
        requestOptions: o,
        type: DioExceptionType.connectionError,
        message: 'The phone is offline.',
      );

  Future<Response<dynamic>?> _cached(RequestOptions o) async {
    final f = _fileFor(o);
    if (f == null) return null;
    final saved = await OfflineStore.readJson(f);
    if (saved is! Map || !saved.containsKey('data')) return null;
    return Response(
      requestOptions: o,
      statusCode: 200,
      data: saved['data'],
      extra: {'fromCache': true, 'savedAt': saved['savedAt']},
    );
  }

  @override
  Future<void> onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    if (!deviceOffline) return handler.next(options);
    if (_cacheable(options)) {
      final hit = await _cached(options);
      if (hit != null) return handler.resolve(hit);
    }
    handler.reject(_offline(options));
  }

  @override
  Future<void> onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) async {
    final o = response.requestOptions;
    final data = response.data;
    if (_cacheable(o) && response.statusCode == 200 && (data is Map || data is List)) {
      final f = _fileFor(o);
      if (f != null) {
        try {
          await OfflineStore.writeJson(f, {'savedAt': DateTime.now().toUtc().toIso8601String(), 'data': data});
        } catch (_) {
          // A full disk only costs the offline copy, never the request itself.
        }
      }
    }
    handler.next(response);
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    // No answer at all (offline, timeout, server asleep) — fall back to the saved copy.
    if (err.response == null && _cacheable(err.requestOptions)) {
      final hit = await _cached(err.requestOptions);
      if (hit != null) return handler.resolve(hit);
    }
    handler.next(err);
  }

  /// Deletes this account's saved answers beyond the newest [keep] (run at sign-in).
  static Future<void> prune({int keep = 600}) async {
    final dir = OfflineStore.instance.accountDir('cache');
    if (dir == null || !await dir.exists()) return;
    final files = await dir.list().where((e) => e is File).cast<File>().toList();
    if (files.length <= keep) return;
    final dated = [for (final f in files) (f, await f.lastModified())]..sort((a, b) => b.$2.compareTo(a.$2));
    for (final (f, _) in dated.skip(keep)) {
      try {
        await f.delete();
      } catch (_) {}
    }
  }
}
