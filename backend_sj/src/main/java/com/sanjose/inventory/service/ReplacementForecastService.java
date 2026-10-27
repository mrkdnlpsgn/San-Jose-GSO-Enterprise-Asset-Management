package com.sanjose.inventory.service;

import com.sanjose.inventory.config.AppTime;
import lombok.RequiredArgsConstructor;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.sql.Date;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.TreeSet;

// Which assets in use will need replacing, and what that will cost, over the next few years.
// An asset's end of life is its acquisition date plus its category's expected life (set on the
// Categories page). Assets already past it, or unserviceable, fall in the "now" bucket; the rest
// fall in the year their life ends. The cost is the acquisition value raised by a yearly price
// increase from the year it was bought to the year it is due. Plain arithmetic; the AI summary
// on Home is written by PlanningInsightService. STAFF only see their own assets.
@Service
@RequiredArgsConstructor
public class ReplacementForecastService {

    private final JdbcTemplate jdbcTemplate;

    public static final int DEFAULT_YEARS = 3;
    public static final double DEFAULT_PRICE_INCREASE = 3.0;
    static final String NOW = "NOW";

    private static final String IN_USE = DashboardService.IN_USE;

    private record Row(long id, String propertyNumber, String description, String category, Long categoryId,
                       Integer life, String office, LocalDate acquired, BigDecimal unitValue, int quantity, String condition) {}

    // years: how many years after this one to look ahead (1-10); priceIncrease: percent per year (0-20).
    public Map<String, Object> forecast(int years, double priceIncrease, boolean withItems, AccessService.StaffScope scope) {
        if (years < 1 || years > 10) throw new IllegalArgumentException("Look ahead between 1 and 10 years.");
        if (priceIncrease < 0 || priceIncrease > 20) throw new IllegalArgumentException("The yearly price increase must be between 0 and 20 percent.");

        LocalDate today = AppTime.today();
        int thisYear = today.getYear();
        int lastYear = thisYear + years;
        double rate = priceIncrease / 100.0;

        List<Row> rows = jdbcTemplate.query(
            "SELECT a.asset_id, a.property_number, a.description, a.acquisition_date, a.unit_value, a.quantity, a.`condition`,"
                + " a.category_id, c.category_name, c.useful_life_years, o.office_name"
                + " FROM assets a LEFT JOIN categories c ON c.category_id = a.category_id"
                + " LEFT JOIN offices o ON o.office_id = a.office_id"
                + " WHERE " + IN_USE + (scope != null ? " AND " + scope.sql("a") : ""),
            (rs, rn) -> {
                Date acq = rs.getDate("acquisition_date");
                return new Row(rs.getLong("asset_id"), rs.getString("property_number"), rs.getString("description"),
                    rs.getString("category_name"), rs.getObject("category_id", Long.class), rs.getObject("useful_life_years", Integer.class),
                    rs.getString("office_name"), acq != null ? acq.toLocalDate() : null, rs.getBigDecimal("unit_value"),
                    Math.max(1, rs.getInt("quantity")), rs.getString("condition"));
            },
            scope != null ? scope.args() : new Object[0]);

        // bucket key -> totals; NOW first, then each year in order
        Map<String, Tally> buckets = new LinkedHashMap<>();
        buckets.put(NOW, new Tally());
        for (int y = thisYear; y <= lastYear; y++) buckets.put(String.valueOf(y), new Tally());
        Map<String, CategoryTally> byCategory = new LinkedHashMap<>();
        Map<String, Tally> byOffice = new LinkedHashMap<>();
        List<Map<String, Object>> items = new ArrayList<>();
        TreeSet<String> noLife = new TreeSet<>();
        int noDate = 0, noValue = 0, later = 0;

        for (Row r : rows) {
            boolean unserviceable = "UNSERVICEABLE".equals(r.condition());
            if (r.life() == null && !unserviceable) { noLife.add(r.category() != null ? r.category() : "Uncategorized"); continue; }
            if (r.acquired() == null && !unserviceable) { noDate++; continue; }
            if (r.unitValue() == null || r.unitValue().signum() <= 0) { noValue++; continue; }

            LocalDate endOfLife = r.acquired() != null && r.life() != null ? r.acquired().plusYears(r.life()) : null;
            String key;
            String reason;
            int dueYear;
            if (unserviceable) {
                key = NOW; reason = "Unserviceable"; dueYear = thisYear;
            } else if (endOfLife.isBefore(today)) {
                key = NOW; reason = "Past expected life"; dueYear = thisYear;
            } else if (endOfLife.getYear() <= lastYear) {
                key = String.valueOf(endOfLife.getYear()); reason = "Expected life ends"; dueYear = endOfLife.getYear();
            } else {
                later++;
                continue;
            }

            int yearsOfIncrease = r.acquired() != null ? Math.max(0, dueYear - r.acquired().getYear()) : 0;
            BigDecimal cost = r.unitValue().multiply(BigDecimal.valueOf(r.quantity()))
                .multiply(BigDecimal.valueOf(Math.pow(1 + rate, yearsOfIncrease)))
                .setScale(2, RoundingMode.HALF_UP);
            boolean repairable = "REPAIRABLE".equals(r.condition());

            buckets.get(key).add(cost, repairable);
            String cat = r.category() != null ? r.category() : "Uncategorized";
            byCategory.computeIfAbsent(cat, k -> new CategoryTally(r.categoryId(), r.life(), buckets.keySet())).add(key, cost, repairable);
            byOffice.computeIfAbsent(r.office() != null ? r.office() : "Unassigned", k -> new Tally()).add(cost, repairable);

            if (withItems) {
                Map<String, Object> it = new LinkedHashMap<>();
                it.put("id", r.id());
                it.put("propertyNumber", r.propertyNumber());
                it.put("description", r.description());
                it.put("category", cat);
                it.put("office", r.office());
                it.put("acquisitionDate", r.acquired() != null ? r.acquired().toString() : null);
                it.put("usefulLifeYears", r.life());
                it.put("endOfLife", endOfLife != null ? endOfLife.toString() : null);
                it.put("replaceIn", key);
                it.put("reason", reason);
                it.put("condition", r.condition());
                it.put("unitValue", r.unitValue());
                it.put("quantity", r.quantity());
                it.put("estimatedCost", cost);
                items.add(it);
            }
        }

        Tally total = new Tally();
        buckets.values().forEach(total::merge);

        Map<String, Object> out = new LinkedHashMap<>();
        out.put("asOf", today.toString());
        out.put("years", years);
        out.put("priceIncreasePercent", priceIncrease);
        out.put("scope", scope == null ? "ALL_OFFICES" : "STAFF_OWN_ASSETS");
        out.put("assetsInUse", rows.size());
        out.put("total", total.toMap());
        out.put("laterThanForecast", later);

        List<Map<String, Object>> bucketList = new ArrayList<>();
        buckets.forEach((k, t) -> {
            Map<String, Object> m = new LinkedHashMap<>();
            m.put("key", k);
            m.put("label", NOW.equals(k) ? "Due now" : k);
            m.putAll(t.toMap());
            bucketList.add(m);
        });
        out.put("buckets", bucketList);

        List<Map<String, Object>> cats = new ArrayList<>();
        byCategory.forEach((name, t) -> cats.add(t.toMap(name)));
        cats.sort(Comparator.comparing((Map<String, Object> m) -> (BigDecimal) m.get("cost")).reversed());
        out.put("byCategory", cats);

        if (scope == null) {
            List<Map<String, Object>> offices = new ArrayList<>();
            byOffice.forEach((name, t) -> {
                Map<String, Object> m = new LinkedHashMap<>();
                m.put("office", name);
                m.putAll(t.toMap());
                offices.add(m);
            });
            offices.sort(Comparator.comparing((Map<String, Object> m) -> (BigDecimal) m.get("cost")).reversed());
            out.put("topOffices", offices.subList(0, Math.min(8, offices.size())));
        }

        Map<String, Object> excluded = new LinkedHashMap<>();
        excluded.put("noExpectedLife", List.copyOf(noLife));
        excluded.put("noExpectedLifeAssets", rows.stream().filter(r -> r.life() == null && !"UNSERVICEABLE".equals(r.condition())).count());
        excluded.put("noAcquisitionDate", noDate);
        excluded.put("noUnitValue", noValue);
        out.put("excluded", excluded);

        if (withItems) {
            items.sort(Comparator.comparing((Map<String, Object> m) -> NOW.equals(m.get("replaceIn")) ? "0" : (String) m.get("replaceIn"))
                .thenComparing(m -> m.get("endOfLife") != null ? (String) m.get("endOfLife") : ""));
            out.put("items", items);
        }
        return out;
    }

    private static final class Tally {
        long assets, repairable;
        BigDecimal cost = BigDecimal.ZERO;

        void add(BigDecimal c, boolean isRepairable) {
            assets++;
            if (isRepairable) repairable++;
            cost = cost.add(c);
        }

        void merge(Tally t) {
            assets += t.assets;
            repairable += t.repairable;
            cost = cost.add(t.cost);
        }

        Map<String, Object> toMap() {
            Map<String, Object> m = new LinkedHashMap<>();
            m.put("assets", assets);
            m.put("cost", cost);
            m.put("repairable", repairable);
            return m;
        }
    }

    private static final class CategoryTally {
        final Long categoryId;
        final Integer life;
        final Tally total = new Tally();
        final Map<String, Tally> perBucket = new LinkedHashMap<>();

        CategoryTally(Long categoryId, Integer life, Iterable<String> keys) {
            this.categoryId = categoryId;
            this.life = life;
            keys.forEach(k -> perBucket.put(k, new Tally()));
        }

        void add(String key, BigDecimal cost, boolean repairable) {
            total.add(cost, repairable);
            perBucket.get(key).add(cost, repairable);
        }

        Map<String, Object> toMap(String name) {
            Map<String, Object> m = new LinkedHashMap<>();
            m.put("categoryId", categoryId);
            m.put("category", name);
            m.put("usefulLifeYears", life);
            m.putAll(total.toMap());
            Map<String, Object> b = new LinkedHashMap<>();
            perBucket.forEach((k, t) -> b.put(k, t.toMap()));
            m.put("buckets", b);
            return m;
        }
    }
}
