import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';

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
