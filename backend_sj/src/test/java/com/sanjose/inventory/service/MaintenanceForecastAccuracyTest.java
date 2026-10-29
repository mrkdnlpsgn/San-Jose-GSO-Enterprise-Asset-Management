package com.sanjose.inventory.service;

import org.junit.jupiter.api.Test;

import java.math.BigDecimal;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;

// The forecast checked against past years: the estimate for year T is the average of T-4 to T-2
// at T's prices, compared with what T actually cost.
class MaintenanceForecastAccuracyTest {

    private static Map<Integer, BigDecimal> totals(int fromYear, long... costs) {
        Map<Integer, BigDecimal> m = new HashMap<>();
        for (int i = 0; i < costs.length; i++) if (costs[i] > 0) m.put(fromYear + i, BigDecimal.valueOf(costs[i]));
        return m;
    }

    @SuppressWarnings("unchecked")
    private static List<Map<String, Object>> years(Map<String, Object> accuracy) {
        return (List<Map<String, Object>>) accuracy.get("years");
    }

    @Test
    void flatSpendingWithNoPriceIncreaseIsExact() {
        // 2019 to 2025, 100,000 every year; this year is 2026
        Map<String, Object> a = MaintenanceForecastService.accuracy(totals(2019, 100000, 100000, 100000, 100000, 100000, 100000, 100000), 2026, 0);
        assertEquals(3, years(a).size());
        assertEquals(2023, years(a).get(0).get("year"));
        assertEquals(0.0, a.get("averageErrorPercent"));
    }

    @Test
    void errorIsSignedPerYearAndAveragedWithoutSign() {
        // base years always average 100,000; 2023 actually cost 80,000, 2024 125,000, 2025 100,000
        Map<String, Object> a = MaintenanceForecastService.accuracy(
            totals(2019, 100000, 100000, 100000, 100000, 80000, 125000, 100000), 2026, 0);
        // 2023: 100,000 vs 80,000 = +25%. 2024: base 2020-2022 = 100,000 vs 125,000 = -20%.
        assertEquals(25.0, years(a).get(0).get("errorPercent"));
        assertEquals(-20.0, years(a).get(1).get("errorPercent"));
        // 2025: base 2021-2023 = (100,000 + 100,000 + 80,000) / 3 = 93,333.33 vs 100,000 = -6.7%
        assertEquals(-6.7, years(a).get(2).get("errorPercent"));
        assertEquals(17.2, a.get("averageErrorPercent"));
    }

    @Test
    void priceIncreaseCoversThreeYears() {
        Map<String, Object> a = MaintenanceForecastService.accuracy(totals(2019, 100000, 100000, 100000, 100000, 100000, 100000, 100000), 2026, 3);
        // 100,000 x 1.03^3
        assertEquals(new BigDecimal("109272.70"), years(a).get(0).get("estimate"));
    }

    @Test
    void yearsWithoutHistoryAreLeftOut() {
        // repairs only recorded from 2023
        Map<String, Object> a = MaintenanceForecastService.accuracy(totals(2023, 50000, 60000, 70000), 2026, 0);
        assertEquals(1, years(a).size());
        assertEquals(2025, years(a).get(0).get("year"));

        Map<String, Object> none = MaintenanceForecastService.accuracy(Map.of(), 2026, 0);
        assertNull(none.get("averageErrorPercent"));
    }
}
