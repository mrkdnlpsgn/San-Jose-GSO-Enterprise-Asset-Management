package com.sanjose.inventory.service;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.LocalDate;
import java.time.temporal.ChronoUnit;

// Straight-line depreciation per COA's Government Accounting Manual: cost is
// depreciated down to a 10% salvage value over the asset category's estimated
// useful life, starting the month after acquisition. Carrying amount never
// reaches zero — it floors at the 10% salvage value, same as the source IIRUP
// records (where "Accumulated Depreciation" stays informational, not a
// disposal trigger; disposal eligibility is gated on physical condition).
public final class DepreciationCalculator {

    private static final BigDecimal SALVAGE_RATE = new BigDecimal("0.10");

    private DepreciationCalculator() {}

    public record Result(BigDecimal accumulatedDepreciation, BigDecimal carryingAmount) {}

    public static Result compute(BigDecimal unitValue, LocalDate acquisitionDate, Integer usefulLifeYears) {
        if (unitValue == null || acquisitionDate == null || usefulLifeYears == null || usefulLifeYears <= 0) {
            return null;
        }

        BigDecimal salvageValue = unitValue.multiply(SALVAGE_RATE);
        BigDecimal depreciableBase = unitValue.subtract(salvageValue);
        int usefulLifeMonths = usefulLifeYears * 12;

        LocalDate depreciationStart = acquisitionDate.withDayOfMonth(1).plusMonths(1);
        long monthsElapsed = ChronoUnit.MONTHS.between(depreciationStart, LocalDate.now().withDayOfMonth(1));
        if (monthsElapsed < 0) monthsElapsed = 0;
        if (monthsElapsed > usefulLifeMonths) monthsElapsed = usefulLifeMonths;

        BigDecimal monthlyDepreciation = depreciableBase.divide(BigDecimal.valueOf(usefulLifeMonths), 4, RoundingMode.HALF_UP);
        BigDecimal accumulatedDepreciation = monthlyDepreciation.multiply(BigDecimal.valueOf(monthsElapsed)).setScale(2, RoundingMode.HALF_UP);
        if (accumulatedDepreciation.compareTo(depreciableBase) > 0) {
            accumulatedDepreciation = depreciableBase.setScale(2, RoundingMode.HALF_UP);
        }

        BigDecimal carryingAmount = unitValue.subtract(accumulatedDepreciation).setScale(2, RoundingMode.HALF_UP);
        return new Result(accumulatedDepreciation, carryingAmount);
    }
}
