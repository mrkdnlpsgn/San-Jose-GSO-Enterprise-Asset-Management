import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../../asset_history/data/asset_history_service.dart';
import '../../asset_history/model/asset_history_model.dart';

/// One office or category and how many in-use assets it holds.
class DashboardGroup {
  final int? id;
  final String name;
  final int count;
  const DashboardGroup(this.id, this.name, this.count);
}

/// One "needs attention" problem: how many assets match, and the first few of them.
class DashboardAttention {
  final int count;
  final List<({int id, String propertyNumber, String description})> items;
  const DashboardAttention(this.count, this.items);

  static const empty = DashboardAttention(0, []);

  factory DashboardAttention.fromJson(Object? json) {
    if (json is! Map) return empty;
    return DashboardAttention(
      (json['count'] as num?)?.toInt() ?? 0,
      [
        for (final m in (json['items'] as List? ?? const []).cast<Map>())
          (
            id: (m['id'] as num).toInt(),
            propertyNumber: m['propertyNumber']?.toString() ?? '',
            description: m['description']?.toString() ?? '',
          ),
      ],
    );
  }
}

/// The web dashboard's numbers, worked out by the server (/api/dashboard/summary) so both
/// apps always agree. Staff get only their own office's assets.
class DashboardStats {
  final int inUse;
  final double totalValue;
  final int newThisMonth;
  final int underRepair;
  final int forDisposal;
  final Map<String, int> conditionDist;
  final List<DashboardGroup> offices;
  final List<DashboardGroup> categories;
  final DashboardAttention unserviceableNoDisposal;
  final DashboardAttention noAccountable;
  final DashboardAttention noOffice;

  const DashboardStats({
    required this.inUse,
    required this.totalValue,
    required this.newThisMonth,
    required this.underRepair,
    required this.forDisposal,
    required this.conditionDist,
    required this.offices,
    required this.categories,
    required this.unserviceableNoDisposal,
    required this.noAccountable,
    required this.noOffice,
  });

  factory DashboardStats.fromJson(Map<String, dynamic> json) {
    int n(Object? v) => (v as num?)?.toInt() ?? 0;
    List<DashboardGroup> groups(Object? list, String idKey, String nameKey) => [
          for (final g in (list as List? ?? const []).cast<Map>())
            DashboardGroup((g[idKey] as num?)?.toInt(), g[nameKey]?.toString() ?? '', n(g['count'])),
        ];
    final attention = json['attention'] as Map? ?? const {};
    return DashboardStats(
      inUse: n(json['inUse']),
      totalValue: (json['totalValue'] as num?)?.toDouble() ?? 0,
      newThisMonth: n(json['newThisMonth']),
      underRepair: n(json['underRepair']),
      forDisposal: n(json['forDisposal']),
      conditionDist: {
        for (final e in (json['condition'] as Map? ?? const {}).entries) e.key.toString(): n(e.value),
      },
      offices: groups(json['offices'], 'officeId', 'office'),
      categories: groups(json['categories'], 'categoryId', 'category'),
      unserviceableNoDisposal: DashboardAttention.fromJson(attention['unserviceableNoDisposal']),
      noAccountable: DashboardAttention.fromJson(attention['noAccountable']),
      noOffice: DashboardAttention.fromJson(attention['noOffice']),
    );
  }
}

final dashboardStatsProvider = FutureProvider.autoDispose<DashboardStats>((ref) async {
  try {
    final res = await ApiClient.instance.dio.get('/dashboard/summary');
    return DashboardStats.fromJson(res.data as Map<String, dynamic>);
  } catch (e) {
    throw ApiException.from(e);
  }
});

/// Recent Activity - the 8 newest history events, as on the web dashboard.
final recentActivityProvider = FutureProvider.autoDispose<List<AssetHistoryModel>>((ref) {
  return AssetHistoryService().getAll(limit: 8);
});

/// Maintenance and disposal over the last 30 days, with the AI summary if one still matches
/// the numbers (web: "Last 30 Days").
class MonthSummary {
  final int maintained;
  final int disposed;
  final String? summary;
  const MonthSummary({required this.maintained, required this.disposed, this.summary});

  factory MonthSummary.fromJson(Map<String, dynamic> json) => MonthSummary(
        maintained: ((json['maintenance'] as Map?)?['assets'] as num?)?.toInt() ?? 0,
        disposed: ((json['disposal'] as Map?)?['assets'] as num?)?.toInt() ?? 0,
        summary: json['summary'] as String?,
      );
}

class MonthSummaryService {
  final Dio _dio = ApiClient.instance.dio;

  Future<MonthSummary> get() async {
    try {
      final res = await _dio.get('/ai-insights/lifecycle', queryParameters: {'range': 'month'});
      return MonthSummary.fromJson(res.data as Map<String, dynamic>);
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  // Writes a new AI summary - the AI has a small daily allowance, so only on request.
  Future<MonthSummary> generate() async {
    try {
      final res = await _dio.post('/ai-insights/lifecycle/summary', queryParameters: {'range': 'month', 'refresh': true});
      return MonthSummary.fromJson(res.data as Map<String, dynamic>);
    } catch (e) {
      throw ApiException.from(e);
    }
  }
}

final monthSummaryProvider = FutureProvider.autoDispose<MonthSummary>((ref) => MonthSummaryService().get());
