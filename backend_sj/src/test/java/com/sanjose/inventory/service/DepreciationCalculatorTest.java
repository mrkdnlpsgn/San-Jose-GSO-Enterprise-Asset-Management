package com.sanjose.inventory.service;

import org.junit.jupiter.api.Test;

import java.math.BigDecimal;
import java.time.LocalDate;

import static org.junit.jupiter.api.Assertions.assertEquals;

// Rows copied from the Accounting Office's printed Buildings schedule, as of November 30, 2024.
class DepreciationCalculatorTest {

    private static final LocalDate AS_OF = LocalDate.of(2024, 11, 30);

    private static void check(String cost, String acquired, int life, String residual, String depreciable,
                              int remaining, String monthly, String expense, String accumulated, String book) {
        DepreciationCalculator.Result r = DepreciationCalculator.compute(new BigDecimal(cost), LocalDate.parse(acquired), life, AS_OF);
        assertEquals(new BigDecimal(residual), r.residualValue(), "residual");
        assertEquals(new BigDecimal(depreciable), r.depreciableCost(), "depreciable");
        assertEquals(remaining, r.remainingLifeMonths(), "remaining");
        if (monthly != null) assertEquals(new BigDecimal(monthly), r.monthlyDepreciation(), "monthly");
        assertEquals(new BigDecimal(expense), r.depreciationExpense(), "expense");
        assertEquals(new BigDecimal(accumulated), r.accumulatedDepreciation(), "accumulated");
        assertEquals(new BigDecimal(book), r.bookValue(), "book value");
    }

    @Test
    void boughtAfterThe15thStartsNextMonth() {
        check("48261667.13", "2019-04-16", 240, "2413083.36", "45848583.77", 173,
            "191035.77", "2101393.47", "12799396.59", "35462270.54");
        check("14978756.09", "2019-05-27", 240, "748937.80", "14229818.29", 174,
            "59290.91", "652200.01", "3913200.06", "11065556.03");
        check("5390502.90", "2022-03-18", 240, "269525.15", "5120977.76", 208,
            "21337.41", "234711.51", "682797.12", "4707705.78");
    }

    @Test
    void boughtOnOrBeforeThe15thStartsThatMonth() {
        check("989940.00", "2022-01-10", 60, "49497.00", "940443.00", 25,
            "15674.05", "172414.55", "548591.75", "441348.25");
        check("29701140.00", "2020-03-12", 240, "1485057.00", "28216083.00", 183,
            "117567.01", "1293237.11", "6701319.57", "22999820.43");
        check("1938320.00", "2022-10-10", 120, "96916.00", "1841404.00", 94,
            "15345.03", "168795.33", "398970.78", "1539349.22");
    }

    @Test
    void fullyDepreciatedStopsAtResidualValue() {
        check("19303867.51", "2018-12-06", 60, "965193.38", "18338674.13", 0,
            null, "0.00", "18338674.13", "965193.38");
        check("114200.00", "2003-12-22", 240, "5710.00", "108490.00", 0,
            null, "0.00", "108490.00", "5710.00");
    }

    @Test
    void notYetStarted() {
        DepreciationCalculator.Result r = DepreciationCalculator.compute(new BigDecimal("1000"), LocalDate.parse("2024-11-20"), 60, AS_OF);
        assertEquals(0, r.monthsUsed());
        assertEquals(new BigDecimal("1000.00"), r.bookValue());
    }
}
