package com.sanjose.inventory.service;

import com.sanjose.inventory.config.AppTime;
import lombok.RequiredArgsConstructor;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

// What repairs and maintenance cost each year, and about how much to budget for them next year
// (the "Repairs and Maintenance" line of the GSO's budget). Counts approved, not deleted records
// with a cost, by their maintenance date. Next year's estimate is a straight-line trend (least
// squares) through the last three full years and this year's spending so far, scaled up to a full
// year by how much of a year's cost is usually spent by this date. It is split among categories by
// their share of those years. The trend label compares the last full year with the first.
// "accuracy" replays the same rule on each of the last 5 full years, using only what was known on
// this date the year before, and compares it with what they actually cost. Plain arithmetic; the AI
// summary on Home is written by PlanningInsightService. STAFF only see their own assets.
@Service
@RequiredArgsConstructor
public class MaintenanceForecastService {

    private final JdbcTemplate jdbcTemplate;

    public static final int HISTORY_YEARS = 3;
    // full years checked by "accuracy"
    private static final int CHECKED_YEARS = 5;
    // this year's spending counts once at least this share of a usual year's cost is in: earlier
    // in the year, scaling it up to a full year would be guesswork
    private static final double MIN_YEAR_SHARE = 0.25;
    // a change of more than this between the first and the last full year counts as a trend
    private static final double TREND_THRESHOLD = 0.15;

    private record Row(int year, long assetId, String category, String office, String type, BigDecimal cost) {}

    public Map<String, Object> forecast(double priceIncrease, AccessService.StaffScope scope) {
        if (priceIncrease < 0 || priceIncrease > 20) throw new IllegalArgumentException("The yearly price increase must be between 0 and 20 percent.");
        LocalDate today = AppTime.today();
        int thisYear = today.getYear();
        int firstYear = thisYear - HISTORY_YEARS;
        int nextYear = thisYear + 1;
        List<Integer> history = new ArrayList<>();
        for (int y = firstYear; y < thisYear; y++) history.add(y);

        List<Row> rows = jdbcTemplate.query(
            "SELECT YEAR(m.maintenance_date) AS y, m.asset_id, c.category_name, o.office_name, m.maintenance_type, m.cost"
                + " FROM maintenance_ledger m JOIN assets a ON a.asset_id = m.asset_id"
                + " LEFT JOIN categories c ON c.category_id = a.category_id"
                + " LEFT JOIN offices o ON o.office_id = a.office_id"
                + " WHERE m.is_deleted = 0 AND m.approval_status = 'APPROVED' AND m.cost > 0"
                + " AND m.maintenance_date >= ? AND m.maintenance_date <= ?"
                + (scope != null ? " AND " + scope.sql("a") : ""),
            (rs, rn) -> new Row(rs.getInt("y"), rs.getLong("asset_id"),
                rs.getString("category_name") != null ? rs.getString("category_name") : "Uncategorized",
                rs.getString("office_name") != null ? rs.getString("office_name") : "Unassigned",
                rs.getString("maintenance_type"), rs.getBigDecimal("cost")),
            args(LocalDate.of(firstYear, 1, 1), today, scope));

        Map<Integer, YearTally> years = new LinkedHashMap<>();
        for (int y = firstYear; y <= thisYear; y++) years.put(y, new YearTally());
        Map<String, Map<Integer, BigDecimal>> byCategory = new LinkedHashMap<>();
        Map<String, BigDecimal> byOffice = new LinkedHashMap<>();
        Map<String, BigDecimal> byType = new LinkedHashMap<>();
        for (Row r : rows) {
            years.get(r.year()).add(r);
            byCategory.computeIfAbsent(r.category(), k -> new LinkedHashMap<>()).merge(r.year(), r.cost(), BigDecimal::add);
            if (r.year() < thisYear) {
                byOffice.merge(r.office(), r.cost(), BigDecimal::add);
                if (r.type() != null) byType.merge(r.type(), r.cost(), BigDecimal::add);
            }
        }

        // next year's total from the trend, split among categories by their share of the history years
        String monthDay = String.format("%02d-%02d", today.getMonthValue(), today.getDayOfMonth());
        Map<Integer, BigDecimal> fullYears = yearTotals(thisYear - CHECKED_YEARS - HISTORY_YEARS - 1, thisYear - 1, scope);
        Map<Integer, BigDecimal> soFar = yearToDateTotals(thisYear - CHECKED_YEARS - HISTORY_YEARS - 1, thisYear, monthDay, scope);
        BigDecimal forecastTotal = estimate(nextYear, fullYears, soFar);
        BigDecimal historyTotal = byCategory.values().stream()
            .map(perYear -> history.stream().map(y -> perYear.getOrDefault(y, BigDecimal.ZERO)).reduce(BigDecimal.ZERO, BigDecimal::add))
            .reduce(BigDecimal.ZERO, BigDecimal::add);

        List<Map<String, Object>> categories = new ArrayList<>();
        for (var e : byCategory.entrySet()) {
            Map<Integer, BigDecimal> perYear = e.getValue();
            BigDecimal sum = history.stream().map(y -> perYear.getOrDefault(y, BigDecimal.ZERO)).reduce(BigDecimal.ZERO, BigDecimal::add);
            BigDecimal average = sum.divide(BigDecimal.valueOf(HISTORY_YEARS), 2, RoundingMode.HALF_UP);
            BigDecimal estimate = historyTotal.signum() == 0 ? BigDecimal.ZERO
                : forecastTotal.multiply(sum).divide(historyTotal, 2, RoundingMode.HALF_UP);

            Map<String, Object> m = new LinkedHashMap<>();
            m.put("category", e.getKey());
            Map<String, Object> costs = new LinkedHashMap<>();
            for (int y = firstYear; y <= thisYear; y++) costs.put(String.valueOf(y), perYear.getOrDefault(y, BigDecimal.ZERO));
            m.put("perYear", costs);
            m.put("average", average);
            m.put("forecast", estimate);
            m.put("trend", trend(perYear.getOrDefault(firstYear, BigDecimal.ZERO), perYear.getOrDefault(thisYear - 1, BigDecimal.ZERO)));
            categories.add(m);
        }
        categories.sort(Comparator.comparing((Map<String, Object> m) -> (BigDecimal) m.get("forecast")).reversed());

        YearTally first = years.get(firstYear), last = years.get(thisYear - 1);
        long yearsWithData = history.stream().filter(y -> years.get(y).cost.signum() > 0).count();
        long historyRecords = history.stream().mapToLong(y -> years.get(y).records).sum();
        BigDecimal historyCost = history.stream().map(y -> years.get(y).cost).reduce(BigDecimal.ZERO, BigDecimal::add);

        Map<String, Object> out = new LinkedHashMap<>();
        out.put("asOf", today.toString());
        out.put("historyYears", history);
        out.put("thisYear", thisYear);
        out.put("nextYear", nextYear);
        out.put("priceIncreasePercent", priceIncrease);
        out.put("scope", scope == null ? "ALL_OFFICES" : "STAFF_OWN_ASSETS");
        List<Map<String, Object>> yearList = new ArrayList<>();
        years.forEach((y, t) -> {
            Map<String, Object> m = t.toMap();
            m.put("year", y);
            m.put("soFar", y == thisYear);
            yearList.add(m);
        });
        out.put("years", yearList);
        out.put("forecast", Map.of("year", nextYear, "cost", forecastTotal));
        out.put("trend", trend(first.cost, last.cost));
        out.put("averageCostPerRepair", historyRecords == 0 ? BigDecimal.ZERO
            : historyCost.divide(BigDecimal.valueOf(historyRecords), 2, RoundingMode.HALF_UP));
        // fewer than two years with any cost: the estimate rests on very little
        out.put("limitedHistory", yearsWithData < 2);
        out.put("byCategory", categories);
        out.put("method", "TREND");
        out.put("accuracy", accuracy(fullYears, soFar, thisYear));
        out.put("byType", sortedDesc(byType, "type"));
        if (scope == null) {
            List<Map<String, Object>> offices = sortedDesc(byOffice, "office");
            out.put("topOffices", offices.subList(0, Math.min(8, offices.size())));
        }
        return out;
    }

    // total cost per year, fromYear to toYear (years with no cost are left out)
    private Map<Integer, BigDecimal> yearTotals(int fromYear, int toYear, AccessService.StaffScope scope) {
        Map<Integer, BigDecimal> totals = new LinkedHashMap<>();
        jdbcTemplate.query(
            "SELECT YEAR(m.maintenance_date) AS y, SUM(m.cost) AS total"
                + " FROM maintenance_ledger m JOIN assets a ON a.asset_id = m.asset_id"
                + " WHERE m.is_deleted = 0 AND m.approval_status = 'APPROVED' AND m.cost > 0"
                + " AND m.maintenance_date >= ? AND m.maintenance_date <= ?"
                + (scope != null ? " AND " + scope.sql("a") : "")
                + " GROUP BY YEAR(m.maintenance_date)",
            rs -> { totals.put(rs.getInt("y"), rs.getBigDecimal("total")); },
            args(LocalDate.of(fromYear, 1, 1), LocalDate.of(toYear, 12, 31), scope));
        return totals;
    }

    // total cost per year up to the same day of the year (monthDay, MM-DD), fromYear to toYear
    private Map<Integer, BigDecimal> yearToDateTotals(int fromYear, int toYear, String monthDay, AccessService.StaffScope scope) {
        Map<Integer, BigDecimal> totals = new LinkedHashMap<>();
        jdbcTemplate.query(
            "SELECT YEAR(m.maintenance_date) AS y, SUM(m.cost) AS total"
                + " FROM maintenance_ledger m JOIN assets a ON a.asset_id = m.asset_id"
                + " WHERE m.is_deleted = 0 AND m.approval_status = 'APPROVED' AND m.cost > 0"
                + " AND m.maintenance_date >= ? AND m.maintenance_date <= ?"
                + " AND DATE_FORMAT(m.maintenance_date, '%m-%d') <= ?"
                + (scope != null ? " AND " + scope.sql("a") : "")
                + " GROUP BY YEAR(m.maintenance_date)",
            rs -> { totals.put(rs.getInt("y"), rs.getBigDecimal("total")); },
            argsWith(LocalDate.of(fromYear, 1, 1), LocalDate.of(toYear, 12, 31), monthDay, scope));
        return totals;
    }

    // The estimate for year T, made during year T-1 on this date: a straight line fitted (least
    // squares) through the full years T-4 to T-2 and year T-1 scaled up from its spending so far,
    // read off at T. Years before the first one with any cost are left out (the system wasn't in use
    // yet). With a single year to go on, that year is the estimate. Never below zero.
    static BigDecimal estimate(int year, Map<Integer, BigDecimal> fullYears, Map<Integer, BigDecimal> soFar) {
        List<double[]> points = new ArrayList<>();
        double fullSum = 0, soFarSum = 0;
        for (int y = year - 1 - HISTORY_YEARS; y <= year - 2; y++) {
            double cost = fullYears.getOrDefault(y, BigDecimal.ZERO).doubleValue();
            if (points.isEmpty() && cost == 0) continue;
            points.add(new double[] {y, cost});
            fullSum += cost;
            soFarSum += soFar.getOrDefault(y, BigDecimal.ZERO).doubleValue();
        }
        double share = fullSum == 0 ? 0 : soFarSum / fullSum;
        double current = soFar.getOrDefault(year - 1, BigDecimal.ZERO).doubleValue();
        if (share >= MIN_YEAR_SHARE && current > 0) points.add(new double[] {year - 1, current / share});
        if (points.isEmpty()) return BigDecimal.ZERO;
        if (points.size() == 1) return BigDecimal.valueOf(points.get(0)[1]).setScale(2, RoundingMode.HALF_UP);
        double mx = points.stream().mapToDouble(p -> p[0]).average().orElse(0);
        double my = points.stream().mapToDouble(p -> p[1]).average().orElse(0);
        double sxy = 0, sxx = 0;
        for (double[] p : points) { sxy += (p[0] - mx) * (p[1] - my); sxx += (p[0] - mx) * (p[0] - mx); }
        double value = my + (sxy / sxx) * (year - mx);
        return BigDecimal.valueOf(Math.max(0, value)).setScale(2, RoundingMode.HALF_UP);
    }

    // How close the method would have been in each of the last 5 full years: the estimate for year
    // T uses only what was known on this date in T-1, set against what T actually cost. A year is
    // left out when it, or all the years before it, had no cost.
    static Map<String, Object> accuracy(Map<Integer, BigDecimal> fullYears, Map<Integer, BigDecimal> soFar, int thisYear) {
        List<Map<String, Object>> checked = new ArrayList<>();
        double errorSum = 0;
        for (int year = thisYear - CHECKED_YEARS; year < thisYear; year++) {
            BigDecimal actual = fullYears.getOrDefault(year, BigDecimal.ZERO);
            BigDecimal estimate = estimate(year, fullYears, soFar);
            if (actual.signum() == 0 || estimate.signum() == 0) continue;
            double error = estimate.subtract(actual).doubleValue() / actual.doubleValue() * 100;
            errorSum += Math.abs(error);
            Map<String, Object> m = new LinkedHashMap<>();
            m.put("year", year);
            m.put("estimate", estimate);
            m.put("actual", actual);
            // positive: the estimate was too high; negative: too low
            m.put("errorPercent", Math.round(error * 10) / 10.0);
            checked.add(m);
        }
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("years", checked);
        out.put("averageErrorPercent", checked.isEmpty() ? null : Math.round(errorSum / checked.size() * 10) / 10.0);
        return out;
    }

    private static Object[] argsWith(LocalDate from, LocalDate to, String extra, AccessService.StaffScope scope) {
        List<Object> a = new ArrayList<>(List.of(java.sql.Date.valueOf(from), java.sql.Date.valueOf(to), extra));
        if (scope != null) a.addAll(java.util.Arrays.asList(scope.args()));
        return a.toArray();
    }

    private static Object[] args(LocalDate from, LocalDate to, AccessService.StaffScope scope) {
        List<Object> a = new ArrayList<>(List.of(java.sql.Date.valueOf(from), java.sql.Date.valueOf(to)));
        if (scope != null) a.addAll(java.util.Arrays.asList(scope.args()));
        return a.toArray();
    }

    static String trend(BigDecimal first, BigDecimal last) {
        if (first.signum() == 0) return last.signum() > 0 ? "RISING" : "STEADY";
        double change = last.subtract(first).doubleValue() / first.doubleValue();
        return change > TREND_THRESHOLD ? "RISING" : change < -TREND_THRESHOLD ? "FALLING" : "STEADY";
    }

    // the 3 full years' totals, largest first
    private static List<Map<String, Object>> sortedDesc(Map<String, BigDecimal> totals, String key) {
        List<Map<String, Object>> list = new ArrayList<>();
        totals.forEach((k, v) -> {
            Map<String, Object> m = new LinkedHashMap<>();
            m.put(key, k);
            m.put("cost", v);
            list.add(m);
        });
        list.sort(Comparator.comparing((Map<String, Object> m) -> (BigDecimal) m.get("cost")).reversed());
        return list;
    }

    private static final class YearTally {
        long records;
        final Set<Long> assets = new HashSet<>();
        BigDecimal cost = BigDecimal.ZERO;

        void add(Row r) {
            records++;
            assets.add(r.assetId());
            cost = cost.add(r.cost());
        }

        Map<String, Object> toMap() {
            Map<String, Object> m = new LinkedHashMap<>();
            m.put("cost", cost);
            m.put("records", records);
            m.put("assets", assets.size());
            return m;
        }
    }
}
