import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../model/audit_log_model.dart';

/// Same endpoints as the web Audit Logs tab (/api/audit-logs, admin only).
class AuditLogService {
  final Dio _dio = ApiClient.instance.dio;

  /// The live log (the last year; older entries are in the archive), newest first.
  Future<List<AuditLogModel>> list({String? search}) async {
    try {
      final q = search?.trim() ?? '';
      final res = await _dio.get('/audit-logs', queryParameters: {if (q.isNotEmpty) 'search': q});
      return (res.data as List).map((e) => AuditLogModel.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  Future<AuditArchiveSummary> archiveSummary() async {
    try {
      final res = await _dio.get('/audit-logs/archive/summary');
      return AuditArchiveSummary.fromJson(res.data as Map<String, dynamic>);
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  /// Moves entries older than the limit to the archive now, instead of waiting for the night.
  Future<AuditArchiveSummary> archiveNow() async {
    try {
      final res = await _dio.post('/audit-logs/archive/run');
      return AuditArchiveSummary.fromJson(res.data as Map<String, dynamic>);
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  static String _day(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Downloads the archive (optionally one date range, Philippine dates) as CSV and opens the
  /// share sheet, so it can be saved to Files, emailed, or opened in a spreadsheet app.
  Future<void> exportArchive({DateTime? from, DateTime? to}) async {
    try {
      final res = await _dio.get<List<int>>(
        '/audit-logs/archive/export',
        queryParameters: {if (from != null) 'from': _day(from), if (to != null) 'to': _day(to)},
        options: Options(responseType: ResponseType.bytes),
      );
      final name = 'audit-logs-archive${from != null ? '-from-${_day(from)}' : ''}'
          '${to != null ? '-to-${_day(to)}' : ''}.csv';
      final file = File('${(await getTemporaryDirectory()).path}/$name');
      await file.writeAsBytes(res.data ?? const [], flush: true);
      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path, mimeType: 'text/csv')], subject: 'Audit logs archive'),
      );
    } catch (e) {
      throw ApiException.from(e);
    }
  }
}
