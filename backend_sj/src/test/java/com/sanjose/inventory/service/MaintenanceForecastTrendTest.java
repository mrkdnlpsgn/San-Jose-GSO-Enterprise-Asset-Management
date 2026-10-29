package com.sanjose.inventory.service;

import org.junit.jupiter.api.Test;

import java.math.BigDecimal;

import static org.junit.jupiter.api.Assertions.assertEquals;

// The repairs and maintenance trend: last full year against the first, rising or falling only
// past a 15% change.
class MaintenanceForecastTrendTest {

    private static String trend(String first, String last) {
        return MaintenanceForecastService.trend(new BigDecimal(first), new BigDecimal(last));
    }

    @Test
    void smallChangesAreSteady() {
        assertEquals("STEADY", trend("100000", "110000"));
        assertEquals("STEADY", trend("100000", "90000"));
        assertEquals("STEADY", trend("100000", "115000"));
    }

    @Test
    void largeChangesShowTheDirection() {
        assertEquals("RISING", trend("100000", "130000"));
        assertEquals("FALLING", trend("100000", "70000"));
    }

    @Test
    void noSpendingInTheFirstYear() {
        assertEquals("RISING", trend("0", "5000"));
        assertEquals("STEADY", trend("0", "0"));
    }
}
