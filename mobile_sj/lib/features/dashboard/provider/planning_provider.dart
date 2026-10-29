import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';

num _num(Object? v) => v is num ? v : num.tryParse('${v ?? ''}') ?? 0;

/// One year (or "due now") of the replacement forecast.
class PlanningBucket {
  final String key; // 'NOW' or a year, e.g. '2027'
  final int assets;
  final double cost;
  const PlanningBucket(this.key, this.assets, this.cost);
}

/// One type of asset and what replacing its due assets would cost.
class PlanningCategory {
  final String name;
  final int assets;
  final double cost;
  const PlanningCategory(this.name, this.assets, this.cost);
}

/// One year of repair and maintenance spending; [soFar] marks this year (not a full year).
class MaintenanceYear {
  final int year;
  final double cost;
  final bool soFar;
  const MaintenanceYear(this.year, this.cost, this.soFar);
}

/// Repair and maintenance spending and next year's estimate (MaintenanceForecastService).
class MaintenancePlan {
  final List<MaintenanceYear> years;
  final int forecastYear;
  final double forecastCost;
  final String trend; // RISING | FALLING | STEADY
  final double priceIncreasePercent;
  final bool limitedHistory;
  final String? topCategory; // costs most to keep running
  const MaintenancePlan({
    required this.years,
    required this.forecastYear,
    required this.forecastCost,
    required this.trend,
    required this.priceIncreasePercent,
    required this.limitedHistory,
    this.topCategory,
  });

  static MaintenancePlan? fromJson(Map? m) {
    if (m == null) return null; // a server from before the forecast
    final f = m['forecast'] as Map? ?? const {};
    final cats = (m['byCategory'] as List? ?? const []).cast<Map>();
    return MaintenancePlan(
      years: [
        for (final y in (m['years'] as List? ?? const []).cast<Map>())
          MaintenanceYear(_num(y['year']).toInt(), _num(y['cost']).toDouble(), y['soFar'] == true),
      ],
      forecastYear: _num(f['year']).toInt(),
      forecastCost: _num(f['cost']).toDouble(),
      trend: '${m['trend'] ?? 'STEADY'}',
      priceIncreasePercent: _num(m['priceIncreasePercent']).toDouble(),
      limitedHistory: m['limitedHistory'] == true,
      topCategory: cats.isEmpty ? null : '${cats.first['category']}',
    );
  }
}

/// Home's "Budget & Planning" (admins only), from /ai-insights/planning: the replacement
/// forecast, repair and maintenance spending, and the book-value totals, plus the AI summary when
/// one still matches the numbers. The same data as the web's Budget & Planning section.
class Planning {
  final String asOf; // 'YYYY-MM-DD'
  final int years;
  final double priceIncreasePercent;
  final List<PlanningBucket> buckets;
  final List<PlanningCategory> categories;
  final List<String> noExpectedLife;
  final int assets;
  final double totalCost;
  final double bookValue;
  final double accumulatedDepreciation;
  final double depreciationExpense;
  final double monthlyDepreciation;
  final int fullyDepreciated;
  final MaintenancePlan? maintenance;
  final String? summary;

  const Planning({
    required this.asOf,
    required this.years,
    required this.priceIncreasePercent,
    required this.buckets,
    required this.categories,
    required this.noExpectedLife,
    required this.assets,
    required this.totalCost,
    required this.bookValue,
    required this.accumulatedDepreciation,
    required this.depreciationExpense,
    required this.monthlyDepreciation,
    required this.fullyDepreciated,
    this.maintenance,
    this.summary,
  });

  PlanningBucket? get dueNow => buckets.where((b) => b.key == 'NOW').firstOrNull;
  List<PlanningBucket> get coming => buckets.where((b) => b.key != 'NOW').toList();

  factory Planning.fromJson(Map<String, dynamic> json) {
    final r = json['replacement'] as Map? ?? const {};
    final dep = json['depreciation'] as Map? ?? const {};
    final d = dep['total'] as Map? ?? const {};
    return Planning(
      asOf: '${dep['asOf'] ?? r['asOf'] ?? ''}',
      years: _num(r['years']).toInt(),
      priceIncreasePercent: _num(r['priceIncreasePercent']).toDouble(),
      buckets: [
        for (final b in (r['buckets'] as List? ?? const []).cast<Map>())
          PlanningBucket('${b['key']}', _num(b['assets']).toInt(), _num(b['cost']).toDouble()),
      ],
      categories: [
        for (final c in (r['byCategory'] as List? ?? const []).cast<Map>())
          PlanningCategory('${c['category']}', _num(c['assets']).toInt(), _num(c['cost']).toDouble()),
      ],
      noExpectedLife: [for (final n in ((r['excluded'] as Map?)?['noExpectedLife'] as List? ?? const [])) '$n'],
      assets: _num(d['assets']).toInt(),
      totalCost: _num(d['totalCost']).toDouble(),
      bookValue: _num(d['bookValue']).toDouble(),
      accumulatedDepreciation: _num(d['accumulatedDepreciation']).toDouble(),
      depreciationExpense: _num(d['depreciationExpense']).toDouble(),
      monthlyDepreciation: _num(d['monthlyDepreciation']).toDouble(),
      fullyDepreciated: _num(d['fullyDepreciated']).toInt(),
      maintenance: MaintenancePlan.fromJson(json['maintenance'] as Map?),
      summary: json['summary'] as String?,
    );
  }
}

class PlanningService {
  Future<Planning> get() async {
    try {
      final res = await ApiClient.instance.dio.get('/ai-insights/planning');
      return Planning.fromJson(res.data as Map<String, dynamic>);
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  // Writes a new AI summary - the AI has a small daily allowance, so only on request.
  Future<Planning> generate() async {
    try {
      final res = await ApiClient.instance.dio.post('/ai-insights/planning/summary', queryParameters: {'refresh': true});
      return Planning.fromJson(res.data as Map<String, dynamic>);
    } catch (e) {
      throw ApiException.from(e);
    }
  }
}

final planningProvider = FutureProvider.autoDispose<Planning>((ref) => PlanningService().get());
