package com.sanjose.inventory.service;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.LocalDate;

// Straight-line depreciation, worked the same way as the Accounting Office's printed schedule
// (Account Code / Total Cost / Residual Value / ... / Book Value, "As of" a date):
//   residual value     = total cost x 5%
//   depreciable cost   = total cost x 95% (worked out on its own, like the sheet's Excel, so it
//                        can differ from cost - residual by a centavo)
//   monthly            = depreciable cost / useful life in months, rounded to centavos
//   start month        = the month acquired when bought on day 1-15, otherwise the next month
//   months used        = start month through the as-of month, counting both, at most the life
//   accumulated        = monthly x months used; the whole depreciable cost once fully used
//   expense (this year) = accumulated as of the date - accumulated as of Dec 31 last year
//   book value         = total cost - accumulated (never below the residual value)
public final class DepreciationCalculator {

    public static final BigDecimal RESIDUAL_RATE = new BigDecimal("0.05");

    private DepreciationCalculator() {}

    public record Result(BigDecimal totalCost, BigDecimal residualValue, BigDecimal depreciableCost,
                         int usefulLifeMonths, int monthsUsed, int remainingLifeMonths,
                         BigDecimal monthlyDepreciation, BigDecimal depreciationExpense,
                         BigDecimal accumulatedDepreciation, BigDecimal bookValue) {
        public boolean fullyDepreciated() { return remainingLifeMonths == 0; }
    }

    public static Result compute(BigDecimal totalCost, LocalDate acquired, int usefulLifeMonths, LocalDate asOf) {
        if (usefulLifeMonths < 1) throw new IllegalArgumentException("Useful life must be at least one month.");
        BigDecimal cost = totalCost.setScale(2, RoundingMode.HALF_UP);
        BigDecimal residual = cost.multiply(RESIDUAL_RATE).setScale(2, RoundingMode.HALF_UP);
        BigDecimal depreciable = cost.multiply(BigDecimal.ONE.subtract(RESIDUAL_RATE)).setScale(2, RoundingMode.HALF_UP);
        BigDecimal monthly = depreciable.divide(BigDecimal.valueOf(usefulLifeMonths), 2, RoundingMode.HALF_UP);

        int used = monthsUsed(acquired, usefulLifeMonths, asOf);
        BigDecimal accumulated = accumulated(depreciable, monthly, used, usefulLifeMonths);
        BigDecimal lastYearEnd = accumulated(depreciable, monthly,
            monthsUsed(acquired, usefulLifeMonths, LocalDate.of(asOf.getYear() - 1, 12, 31)), usefulLifeMonths);

        return new Result(cost, residual, depreciable, usefulLifeMonths, used, usefulLifeMonths - used,
            monthly, accumulated.subtract(lastYearEnd), accumulated, cost.subtract(accumulated));
    }

    static int monthsUsed(LocalDate acquired, int lifeMonths, LocalDate asOf) {
        LocalDate start = acquired.getDayOfMonth() <= 15
            ? acquired.withDayOfMonth(1)
            : acquired.withDayOfMonth(1).plusMonths(1);
        long months = (asOf.getYear() - start.getYear()) * 12L + asOf.getMonthValue() - start.getMonthValue() + 1;
        return (int) Math.max(0, Math.min(lifeMonths, months));
    }

    private static BigDecimal accumulated(BigDecimal depreciable, BigDecimal monthly, int used, int lifeMonths) {
        return used >= lifeMonths ? depreciable : monthly.multiply(BigDecimal.valueOf(used));
    }
}
