package com.sanjose.inventory.service;

import com.sanjose.inventory.config.AppTime;
import lombok.RequiredArgsConstructor;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;

import java.math.BigDecimal;
import java.sql.Date;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.TreeSet;

// Depreciation schedule of the assets in use as of a date, in the Accounting Office's printed
// layout (see DepreciationCalculator for the formulas). The useful life is the category's
// expected life in years x 12. Totals per category, plus the item rows for the report. The AI
// summary on Home is written by PlanningInsightService. STAFF only see their own assets.
@Service
@RequiredArgsConstructor
public class DepreciationService {

    private final JdbcTemplate jdbcTemplate;

    private static final String IN_USE = DashboardService.IN_USE;

    public Map<String, Object> schedule(LocalDate asOf, boolean withItems, AccessService.StaffScope scope) {
        LocalDate date = asOf != null ? asOf : AppTime.today();

        Map<String, Totals> byCategory = new LinkedHashMap<>();
        Totals all = new Totals();
        List<Map<String, Object>> items = new ArrayList<>();
        TreeSet<String> noLife = new TreeSet<>();
        int[] skipped = new int[3]; // no expected life, no acquisition date, no value / bought after the date

        jdbcTemplate.query(
            "SELECT a.asset_id, a.property_number, a.description, a.acquisition_date, a.unit_value, a.quantity,"
                + " c.category_id, c.category_name, c.useful_life_years, o.office_name"
                + " FROM assets a LEFT JOIN categories c ON c.category_id = a.category_id"
                + " LEFT JOIN offices o ON o.office_id = a.office_id"
                + " WHERE " + IN_USE + (scope != null ? " AND " + scope.sql("a") : "")
                + " ORDER BY c.category_name, a.acquisition_date, a.property_number",
            rs -> {
                String category = rs.getString("category_name") != null ? rs.getString("category_name") : "Uncategorized";
                Integer years = rs.getObject("useful_life_years", Integer.class);
                Date acq = rs.getDate("acquisition_date");
                BigDecimal unitValue = rs.getBigDecimal("unit_value");
                if (years == null) { noLife.add(category); skipped[0]++; return; }
                if (acq == null) { skipped[1]++; return; }
                if (unitValue == null || unitValue.signum() <= 0 || acq.toLocalDate().isAfter(date)) { skipped[2]++; return; }

                BigDecimal cost = unitValue.multiply(BigDecimal.valueOf(Math.max(1, rs.getInt("quantity"))));
                DepreciationCalculator.Result r = DepreciationCalculator.compute(cost, acq.toLocalDate(), years * 12, date);
                all.add(r);
                byCategory.computeIfAbsent(category, k -> new Totals()).add(r);

                if (withItems) {
                    Map<String, Object> it = new LinkedHashMap<>();
                    it.put("id", rs.getLong("asset_id"));
                    it.put("propertyNumber", rs.getString("property_number"));
                    it.put("description", rs.getString("description"));
                    it.put("category", category);
                    it.put("office", rs.getString("office_name"));
                    it.put("acquisitionDate", acq.toLocalDate().toString());
                    it.put("totalCost", r.totalCost());
                    it.put("residualValue", r.residualValue());
                    it.put("depreciableCost", r.depreciableCost());
                    it.put("usefulLifeMonths", r.usefulLifeMonths());
                    it.put("remainingLifeMonths", r.remainingLifeMonths());
                    it.put("monthlyDepreciation", r.fullyDepreciated() ? null : r.monthlyDepreciation());
                    it.put("depreciationExpense", r.depreciationExpense());
                    it.put("accumulatedDepreciation", r.accumulatedDepreciation());
                    it.put("bookValue", r.bookValue());
                    items.add(it);
                }
            },
            scope != null ? scope.args() : new Object[0]);

        Map<String, Object> out = new LinkedHashMap<>();
        out.put("asOf", date.toString());
        out.put("scope", scope == null ? "ALL_OFFICES" : "STAFF_OWN_ASSETS");
        out.put("residualRatePercent", 5);
        out.put("total", all.toMap());

        List<Map<String, Object>> cats = new ArrayList<>();
        byCategory.forEach((name, t) -> {
            Map<String, Object> m = new LinkedHashMap<>();
            m.put("category", name);
            m.putAll(t.toMap());
            cats.add(m);
        });
        cats.sort(Comparator.comparing((Map<String, Object> m) -> (BigDecimal) m.get("accumulatedDepreciation")).reversed());
        out.put("byCategory", cats);

        Map<String, Object> excluded = new LinkedHashMap<>();
        excluded.put("noExpectedLife", List.copyOf(noLife));
        excluded.put("noExpectedLifeAssets", skipped[0]);
        excluded.put("noAcquisitionDate", skipped[1]);
        excluded.put("noValueOrNotYetAcquired", skipped[2]);
        out.put("excluded", excluded);

        if (withItems) out.put("items", items);
        return out;
    }

    private static final class Totals {
        long assets, fullyDepreciated;
        BigDecimal cost = BigDecimal.ZERO, residual = BigDecimal.ZERO, expense = BigDecimal.ZERO,
            accumulated = BigDecimal.ZERO, book = BigDecimal.ZERO, monthly = BigDecimal.ZERO;

        void add(DepreciationCalculator.Result r) {
            assets++;
            if (r.fullyDepreciated()) fullyDepreciated++;
            else monthly = monthly.add(r.monthlyDepreciation());
            cost = cost.add(r.totalCost());
            residual = residual.add(r.residualValue());
            expense = expense.add(r.depreciationExpense());
            accumulated = accumulated.add(r.accumulatedDepreciation());
            book = book.add(r.bookValue());
        }

        Map<String, Object> toMap() {
            Map<String, Object> m = new LinkedHashMap<>();
            m.put("assets", assets);
            m.put("fullyDepreciated", fullyDepreciated);
            m.put("totalCost", cost);
            m.put("residualValue", residual);
            m.put("monthlyDepreciation", monthly);
            m.put("depreciationExpense", expense);
            m.put("accumulatedDepreciation", accumulated);
            m.put("bookValue", book);
            return m;
        }
    }
}
