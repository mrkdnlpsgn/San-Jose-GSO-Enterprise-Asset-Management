package com.sanjose.inventory.service;

import com.sanjose.inventory.config.AppTime;
import lombok.RequiredArgsConstructor;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;

import java.math.BigDecimal;
import java.sql.Date;
import java.sql.Timestamp;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Comparator;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

// Which assets in use are likely to need repair or maintenance in the next 12 months: a
// machine-learning model (logistic regression) trained on the system's own records. "Needed
// work" in a year = at least one approved, not deleted maintenance record with a cost, the same
// records the repairs budget counts. Training rows are every asset on hand on 1 January of past
// years, described only by what was known that day (age, work done in the year and the 2 years
// before, cost of that work, how often that kind of property needed work the year before, its
// value) and labelled by whether it needed work in the 12 months after. Before it is used, the
// model is checked on last year: trained without it, then compared with what really happened.
// Training uses every office's records; STAFF only see their own assets in the list.
@Service
@RequiredArgsConstructor
public class RepairRiskService {

    private final JdbcTemplate jdbcTemplate;

    static final String[] FEATURES = {"age", "workLastYear", "workBefore", "costLast3Years", "kindRate", "value"};
    // past years used as training snapshots (1 January of each)
    private static final int TRAIN_YEARS = 5;
    // fewer assets that needed work than this in the training rows: too little to learn from
    private static final int MIN_POSITIVES = 20;
    static final double HIGH = 0.5, MEDIUM = 0.2;
    private static final long CACHE_MS = 10 * 60 * 1000;

    record Asset(long id, String propertyNumber, String description, String category, String kind,
                 String office, long acquired, long gone, double value, long[] workDays, double[] workCosts) {}

    record Model(double[] mean, double[] std, double[] w, double bias) {
        double chance(double[] x) {
            double z = bias;
            for (int j = 0; j < x.length; j++) z += w[j] * (x[j] - mean[j]) / std[j];
            return 1 / (1 + Math.exp(-z));
        }
    }

    private record Trained(LocalDate day, long at, Model model, Map<String, Object> check, int rows,
                           List<Asset> assets, Map<String, Double> kindRateNow) {}

    private volatile Trained cache;

    public Map<String, Object> forecast(boolean items, AccessService.StaffScope scope) {
        Trained t = trained();
        LocalDate today = AppTime.today();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("asOf", today.toString());
        out.put("until", today.plusYears(1).toString());
        if (t.model == null) {
            out.put("notEnoughHistory", true);
            return out;
        }
        out.put("notEnoughHistory", false);
        out.put("trainingRows", t.rows);
        out.put("check", t.check);
        out.put("factors", factors(t.model));

        Set<Long> inScope = new HashSet<>(jdbcTemplate.queryForList(
            "SELECT a.asset_id FROM assets a WHERE " + DashboardService.IN_USE + (scope != null ? " AND " + scope.sql("a") : ""),
            Long.class, scope != null ? scope.args() : new Object[0]));
        long now = today.toEpochDay();
        List<Map<String, Object>> list = new ArrayList<>();
        double expected = 0;
        int high = 0, medium = 0, total = 0;
        for (Asset a : t.assets) {
            if (!inScope.contains(a.id) || a.acquired > now) continue;
            double[] x = features(a, now, t.kindRateNow);
            double p = t.model.chance(x);
            expected += p;
            total++;
            if (p >= HIGH) high++; else if (p >= MEDIUM) medium++; else continue;
            if (!items) continue;
            Map<String, Object> m = new LinkedHashMap<>();
            m.put("assetId", a.id);
            m.put("propertyNumber", a.propertyNumber);
            m.put("description", a.description);
            m.put("category", a.category);
            m.put("office", a.office);
            m.put("ageYears", (int) Math.floor(x[0]));
            m.put("chancePercent", (int) Math.round(p * 100));
            m.put("level", p >= HIGH ? "HIGH" : "MEDIUM");
            m.put("reasons", reasons(t.model, x, a));
            list.add(m);
        }
        out.put("assets", total);
        out.put("expectedAssets", (int) Math.round(expected));
        out.put("high", high);
        out.put("medium", medium);
        if (items) {
            list.sort(Comparator.comparingInt((Map<String, Object> m) -> (Integer) m.get("chancePercent")).reversed());
            out.put("items", list);
        }
        return out;
    }

    private Trained trained() {
        LocalDate today = AppTime.today();
        Trained t = cache;
        if (t != null && t.day.equals(today) && System.currentTimeMillis() - t.at < CACHE_MS) return t;
        List<Asset> assets = load();
        int thisYear = today.getYear();
        // check: trained on the years before last year, tested on last year
        List<double[]> trainX = new ArrayList<>();
        List<Boolean> trainY = new ArrayList<>();
        for (int y = thisYear - 1 - TRAIN_YEARS; y < thisYear - 1; y++) snapshot(assets, LocalDate.of(y, 1, 1).toEpochDay(), trainX, trainY);
        Model checkModel = trainY.stream().filter(b -> b).count() >= MIN_POSITIVES ? fit(trainX, trainY) : null;
        Map<String, Object> check = null;
        if (checkModel != null) {
            List<double[]> testX = new ArrayList<>();
            List<Boolean> testY = new ArrayList<>();
            snapshot(assets, LocalDate.of(thisYear - 1, 1, 1).toEpochDay(), testX, testY);
            check = check(checkModel, testX, testY, thisYear - 1);
        }
        // the model in use also learns from last year
        LocalDate lastSnapshot = LocalDate.of(thisYear - 1, 1, 1);
        if (today.isBefore(lastSnapshot.plusYears(1))) lastSnapshot = lastSnapshot.minusYears(1);
        List<double[]> allX = new ArrayList<>();
        List<Boolean> allY = new ArrayList<>();
        for (int y = thisYear - 1 - TRAIN_YEARS; y <= lastSnapshot.getYear(); y++) snapshot(assets, LocalDate.of(y, 1, 1).toEpochDay(), allX, allY);
        Model model = allY.stream().filter(b -> b).count() >= MIN_POSITIVES ? fit(allX, allY) : null;
        t = new Trained(today, System.currentTimeMillis(), model, check, allX.size(), assets, kindRates(assets, today.toEpochDay()));
        cache = t;
        return t;
    }

    private List<Asset> load() {
        Map<Long, List<long[]>> work = new HashMap<>();
        Map<Long, List<Double>> costs = new HashMap<>();
        jdbcTemplate.query(
            "SELECT asset_id, maintenance_date, cost FROM maintenance_ledger"
                + " WHERE is_deleted = 0 AND approval_status = 'APPROVED' AND cost > 0 AND maintenance_date IS NOT NULL"
                + " ORDER BY maintenance_date",
            rs -> {
                long id = rs.getLong("asset_id");
                work.computeIfAbsent(id, k -> new ArrayList<>()).add(new long[]{rs.getDate("maintenance_date").toLocalDate().toEpochDay()});
                costs.computeIfAbsent(id, k -> new ArrayList<>()).add(rs.getBigDecimal("cost").doubleValue());
            });
        List<Object[]> raw = new ArrayList<>();
        Map<String, Integer> articleCount = new HashMap<>();
        jdbcTemplate.query(
            "SELECT a.asset_id, a.property_number, a.description, a.acquisition_date, a.unit_value,"
                + " c.category_name, ar.article_name, o.office_name,"
                + " (SELECT MIN(d.created_at) FROM disposal_ledger d WHERE d.asset_id = a.asset_id AND d.is_deleted = 0"
                + "   AND d.approval_status <> 'REJECTED' AND d.disposal_status = 'COMPLETED') AS gone_at"
                + " FROM assets a LEFT JOIN categories c ON c.category_id = a.category_id"
                + " LEFT JOIN articles ar ON ar.article_id = a.article_id"
                + " LEFT JOIN offices o ON o.office_id = a.office_id"
                + " WHERE a.is_deleted = 0 AND a.acquisition_date IS NOT NULL",
            rs -> {
                Date acq = rs.getDate("acquisition_date");
                Timestamp gone = rs.getTimestamp("gone_at");
                BigDecimal v = rs.getBigDecimal("unit_value");
                String article = rs.getString("article_name");
                if (article != null) articleCount.merge(article, 1, Integer::sum);
                raw.add(new Object[]{rs.getLong("asset_id"), rs.getString("property_number"), rs.getString("description"),
                    rs.getString("category_name") != null ? rs.getString("category_name") : "Uncategorized", article,
                    rs.getString("office_name"), acq.toLocalDate().toEpochDay(),
                    gone != null ? gone.toLocalDateTime().toLocalDate().toEpochDay() : Long.MAX_VALUE,
                    v != null ? v.doubleValue() : 0});
            });
        List<Asset> assets = new ArrayList<>(raw.size());
        for (Object[] r : raw) {
            long id = (Long) r[0];
            String article = (String) r[4];
            // a kind of property with fewer than 10 assets is grouped with its category
            String kind = article != null && articleCount.get(article) >= 10 ? article : (String) r[3];
            List<long[]> w = work.getOrDefault(id, List.of());
            List<Double> c = costs.getOrDefault(id, List.of());
            assets.add(new Asset(id, (String) r[1], (String) r[2], (String) r[3], kind, (String) r[5], (Long) r[6], (Long) r[7],
                (Double) r[8], w.stream().mapToLong(x -> x[0]).toArray(), c.stream().mapToDouble(Double::doubleValue).toArray()));
        }
        return assets;
    }

    private static boolean onHand(Asset a, long day) {
        return a.acquired < day && a.gone >= day;
    }

    private static int count(long[] days, long from, long to) {
        int n = 0;
        for (long d : days) if (d >= from && d < to) n++;
        return n;
    }

    // for each kind of property: the share of those on hand a year before `day` that needed work in that year
    static Map<String, Double> kindRates(List<Asset> assets, long day) {
        Map<String, int[]> counts = new HashMap<>();
        for (Asset a : assets) {
            if (!onHand(a, day - 365)) continue;
            int[] c = counts.computeIfAbsent(a.kind, k -> new int[2]);
            c[0]++;
            if (count(a.workDays, day - 365, day) > 0) c[1]++;
        }
        Map<String, Double> rates = new HashMap<>();
        counts.forEach((k, c) -> rates.put(k, (double) c[1] / c[0]));
        return rates;
    }

    // what was known about the asset on `day`: nothing from that day on is used
    static double[] features(Asset a, long day, Map<String, Double> kindRate) {
        double cost = 0;
        for (int i = 0; i < a.workDays.length; i++) if (a.workDays[i] >= day - 3 * 365 && a.workDays[i] < day) cost += a.workCosts[i];
        return new double[]{
            Math.min(30, (day - a.acquired) / 365.25),
            count(a.workDays, day - 365, day),
            count(a.workDays, day - 3 * 365, day - 365),
            Math.log1p(cost / 1000),
            kindRate.getOrDefault(a.kind, 0.0),
            Math.log1p(a.value / 1000),
        };
    }

    private static void snapshot(List<Asset> assets, long day, List<double[]> xs, List<Boolean> ys) {
        Map<String, Double> rates = kindRates(assets, day);
        for (Asset a : assets) {
            if (!onHand(a, day)) continue;
            xs.add(features(a, day, rates));
            ys.add(count(a.workDays, day, day + 365) > 0);
        }
    }

    // logistic regression on standardized features, by gradient descent with a small L2 penalty
    static Model fit(List<double[]> xs, List<Boolean> ys) {
        int n = xs.size(), k = FEATURES.length;
        double[] mean = new double[k], std = new double[k];
        for (double[] x : xs) for (int j = 0; j < k; j++) mean[j] += x[j] / n;
        for (double[] x : xs) for (int j = 0; j < k; j++) std[j] += (x[j] - mean[j]) * (x[j] - mean[j]) / n;
        for (int j = 0; j < k; j++) std[j] = std[j] > 1e-12 ? Math.sqrt(std[j]) : 1;
        double[][] z = new double[n][k];
        for (int i = 0; i < n; i++) for (int j = 0; j < k; j++) z[i][j] = (xs.get(i)[j] - mean[j]) / std[j];
        double[] w = new double[k];
        double b = 0, rate = 0.5, l2 = 1e-3;
        for (int iter = 0; iter < 1500; iter++) {
            double[] g = new double[k];
            double gb = 0;
            for (int i = 0; i < n; i++) {
                double s = b;
                for (int j = 0; j < k; j++) s += w[j] * z[i][j];
                double err = 1 / (1 + Math.exp(-s)) - (ys.get(i) ? 1 : 0);
                gb += err;
                for (int j = 0; j < k; j++) g[j] += err * z[i][j];
            }
            b -= rate * gb / n;
            for (int j = 0; j < k; j++) w[j] -= rate * (g[j] / n + l2 * w[j]);
        }
        return new Model(mean, std, w, b);
    }

    // How the model did on last year. Its top list is as long as the number of assets that
    // really needed work, so "found" is both how many of its picks were right and how many of the
    // real cases it caught. AUC: the chance it ranks a random asset that needed work above one that didn't.
    static Map<String, Object> check(Model model, List<double[]> xs, List<Boolean> ys, int year) {
        int n = xs.size();
        Integer[] order = new Integer[n];
        double[] p = new double[n];
        double expected = 0;
        int actual = 0;
        for (int i = 0; i < n; i++) {
            order[i] = i;
            p[i] = model.chance(xs.get(i));
            expected += p[i];
            if (ys.get(i)) actual++;
        }
        Arrays.sort(order, (a, b) -> Double.compare(p[b], p[a]));
        int found = 0;
        for (int r = 0; r < actual; r++) if (ys.get(order[r])) found++;
        // AUC by ranks (ties share the average rank)
        double rankSum = 0;
        for (int r = 0; r < n; ) {
            int s = r;
            while (r < n && p[order[r]] == p[order[s]]) r++;
            double avgRank = n - (s + r - 1) / 2.0; // rank 1 = lowest chance
            for (int q = s; q < r; q++) if (ys.get(order[q])) rankSum += avgRank;
        }
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("year", year);
        m.put("assets", n);
        m.put("needed", actual);
        m.put("expected", (int) Math.round(expected));
        m.put("found", found);
        m.put("foundPercent", actual == 0 ? null : Math.round(found * 1000.0 / actual) / 10.0);
        m.put("randomPercent", n == 0 ? null : Math.round(actual * 1000.0 / n) / 10.0);
        long negatives = n - actual;
        m.put("auc", actual == 0 || negatives == 0 ? null
            : Math.round((rankSum - actual * (actual + 1) / 2.0) / (actual * (double) negatives) * 100) / 100.0);
        return m;
    }

    private static final Map<String, String> FACTOR_LABEL = Map.of(
        "age", "Older assets",
        "workLastYear", "Worked on in the past 12 months",
        "workBefore", "Worked on 1 to 3 years ago",
        "costLast3Years", "More spent on it in the last 3 years",
        "kindRate", "Kinds of property that often need work",
        "value", "Higher-value assets");

    // what the model learned: each factor and whether it raises or lowers the chance
    private static List<Map<String, Object>> factors(Model model) {
        List<Map<String, Object>> list = new ArrayList<>();
        for (int j = 0; j < FEATURES.length; j++) {
            Map<String, Object> m = new LinkedHashMap<>();
            m.put("factor", FACTOR_LABEL.get(FEATURES[j]));
            m.put("weight", Math.round(model.w[j] * 100) / 100.0);
            list.add(m);
        }
        list.sort(Comparator.comparingDouble((Map<String, Object> m) -> -Math.abs((Double) m.get("weight"))));
        return list;
    }

    // up to 2 plain reasons: the factors that raise this asset's chance the most. Only "more of it
    // means more work" factors on which the asset is above average count, so a reason never reads
    // like "0 years old" when the model happens to find newer assets busier.
    static List<String> reasons(Model model, double[] x, Asset a) {
        List<double[]> parts = new ArrayList<>();
        for (int j = 0; j < x.length; j++)
            if (model.w[j] > 0 && x[j] > model.mean[j]) parts.add(new double[]{j, model.w[j] * (x[j] - model.mean[j]) / model.std[j]});
        parts.sort((u, v) -> Double.compare(v[1], u[1]));
        List<String> out = new ArrayList<>();
        for (double[] part : parts) {
            if (out.size() == 2 || part[1] < 0.15) break;
            int j = (int) part[0];
            out.add(switch (FEATURES[j]) {
                case "age" -> (int) Math.floor(x[0]) + ((int) Math.floor(x[0]) == 1 ? " year old" : " years old");
                case "workLastYear" -> "Repaired " + times((int) x[1]) + " in the past year";
                case "workBefore" -> "Repaired " + times((int) x[2]) + " 1 to 3 years ago";
                case "costLast3Years" -> String.format("P%,.0f spent on repairs in the last 3 years", Math.expm1(x[3]) * 1000).replace("P", "₱");
                case "kindRate" -> "Items like this often need repair (" + Math.round(x[4] * 100) + " in 100 last year)";
                default -> String.format("Expensive item (₱%,.0f)", a.value);
            });
        }
        return out;
    }

    private static String times(int n) {
        return n == 1 ? "once" : n == 2 ? "twice" : n + " times";
    }
}
