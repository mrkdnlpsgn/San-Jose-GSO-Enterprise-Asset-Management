package com.sanjose.inventory.service;

import org.junit.jupiter.api.Test;

import java.math.BigDecimal;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;

// The repairs estimate: a straight-line trend through the full years T-4 to T-2 and year T-1
// scaled up from its spending so far, and that same rule checked against past years.
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
    void flatSpendingIsExact() {
        // 100,000 every year, half of it spent by this date each year; this year is 2026
        Map<Integer, BigDecimal> full = totals(2016, 100000, 100000, 100000, 100000, 100000, 100000, 100000, 100000, 100000, 100000);
        Map<Integer, BigDecimal> soFar = totals(2016, 50000, 50000, 50000, 50000, 50000, 50000, 50000, 50000, 50000, 50000, 50000);
        assertEquals(new BigDecimal("100000.00"), MaintenanceForecastService.estimate(2027, full, soFar));
        Map<String, Object> a = MaintenanceForecastService.accuracy(full, soFar, 2026);
        assertEquals(5, years(a).size());
        assertEquals(2021, years(a).get(0).get("year"));
        assertEquals(0.0, a.get("averageErrorPercent"));
    }

    @Test
    void steadyGrowthIsCarriedForward() {
        // +10,000 a year: 2023 100k, 2024 110k, 2025 120k, and 2026 on pace for 130k (half by this date)
        Map<Integer, BigDecimal> full = totals(2023, 100000, 110000, 120000);
        Map<Integer, BigDecimal> soFar = totals(2023, 50000, 55000, 60000, 65000);
        assertEquals(new BigDecimal("140000.00"), MaintenanceForecastService.estimate(2027, full, soFar));
    }

    @Test
    void thisYearCountsOnlyOnceEnoughOfItIsIn() {
        // early in the year (5% of a usual year spent so far) the line runs through the full years only
        Map<Integer, BigDecimal> full = totals(2023, 100000, 110000, 120000);
        Map<Integer, BigDecimal> soFar = totals(2023, 5000, 5500, 6000, 1000);
        assertEquals(new BigDecimal("140000.00"), MaintenanceForecastService.estimate(2027, full, soFar));
    }

    @Test
    void errorIsSignedPerYearAndAveragedWithoutSign() {
        // flat 100,000 with nothing known early in each year, then 2025 cost 125,000
        Map<Integer, BigDecimal> full = totals(2016, 100000, 100000, 100000, 100000, 100000, 100000, 100000, 100000, 100000, 125000);
        Map<String, Object> a = MaintenanceForecastService.accuracy(full, Map.of(), 2026);
        // 2025 was estimated at 100,000 against 125,000 actual: 20% too low; the other years exact
        assertEquals(-20.0, years(a).get(4).get("errorPercent"));
        assertEquals(4.0, a.get("averageErrorPercent"));
    }

    @Test
    void yearsWithoutHistoryAreLeftOut() {
        // repairs only recorded from 2023: 2025 is the only year with a year before it to go on
        Map<String, Object> a = MaintenanceForecastService.accuracy(totals(2023, 50000, 60000, 70000), Map.of(), 2026);
        assertEquals(1, years(a).size());
        assertEquals(2025, years(a).get(0).get("year"));

        Map<String, Object> none = MaintenanceForecastService.accuracy(Map.of(), Map.of(), 2026);
        assertNull(none.get("averageErrorPercent"));
        assertEquals(BigDecimal.ZERO, MaintenanceForecastService.estimate(2027, Map.of(), Map.of()));
    }

    @Test
    void neverBelowZero() {
        Map<Integer, BigDecimal> falling = totals(2023, 300000, 150000, 10000);
        assertEquals(new BigDecimal("0.00"), MaintenanceForecastService.estimate(2027, falling, Map.of()));
    }
}
