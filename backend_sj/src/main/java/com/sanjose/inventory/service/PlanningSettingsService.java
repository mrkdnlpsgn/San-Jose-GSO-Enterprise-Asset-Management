package com.sanjose.inventory.service;

import jakarta.annotation.PostConstruct;
import lombok.RequiredArgsConstructor;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;

import java.util.List;

// Budget planning settings an administrator sets on Home > Budget & Planning. For now the yearly
// price increase used by the replacement and the repairs and maintenance forecasts (default 3%,
// the middle of the BSP's 2-4% inflation target); the Budget Office may give its own rate for the
// budget call. Kept in a small key/value table created here at startup, like the other tables
// added after the schema scripts (a fresh or hosted database gets it on the next deploy).
@Service
@RequiredArgsConstructor
public class PlanningSettingsService {

    private static final String PRICE_INCREASE = "planning.price_increase_percent";
    public static final double DEFAULT_PRICE_INCREASE = 3.0;
    public static final double MAX_PRICE_INCREASE = 20.0;

    private final JdbcTemplate jdbcTemplate;
    private final AuditLogService auditLogService;

    @PostConstruct
    void ensureTable() {
        jdbcTemplate.execute("""
            CREATE TABLE IF NOT EXISTS app_settings (
              setting_key   VARCHAR(64)  NOT NULL PRIMARY KEY,
              setting_value VARCHAR(255) NOT NULL,
              updated_by    INT NULL,
              updated_at    DATETIME NOT NULL
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci
            """);
    }

    public double priceIncreasePercent() {
        List<String> v = jdbcTemplate.queryForList(
            "SELECT setting_value FROM app_settings WHERE setting_key = ?", String.class, PRICE_INCREASE);
        if (v.isEmpty()) return DEFAULT_PRICE_INCREASE;
        try {
            double d = Double.parseDouble(v.get(0));
            return d >= 0 && d <= MAX_PRICE_INCREASE ? d : DEFAULT_PRICE_INCREASE;
        } catch (NumberFormatException e) {
            return DEFAULT_PRICE_INCREASE;
        }
    }

    // percent: 0-20, kept to one decimal place
    public double setPriceIncreasePercent(Double percent, Long userId) {
        if (percent == null || percent.isNaN() || percent < 0 || percent > MAX_PRICE_INCREASE) {
            throw new IllegalArgumentException("The yearly price increase must be between 0 and 20 percent.");
        }
        double rounded = Math.round(percent * 10) / 10.0;
        double before = priceIncreasePercent();
        jdbcTemplate.update("""
            INSERT INTO app_settings (setting_key, setting_value, updated_by, updated_at) VALUES (?, ?, ?, NOW())
            ON DUPLICATE KEY UPDATE setting_value = VALUES(setting_value), updated_by = VALUES(updated_by), updated_at = NOW()""",
            PRICE_INCREASE, String.valueOf(rounded), userId);
        auditLogService.log("PLANNING_PRICE_INCREASE_CHANGED", "Planning", userId, "setting",
            "Yearly price increase for budget forecasts changed from " + fmt(before) + "% to " + fmt(rounded) + "%");
        return rounded;
    }

    static String fmt(double d) {
        return d == Math.rint(d) ? String.valueOf((long) d) : String.valueOf(d);
    }
}
