package com.sanjose.inventory.service;

import com.sanjose.inventory.dto.MaintenanceItem;
import com.sanjose.inventory.entity.MaintenanceLedger;
import jakarta.annotation.PostConstruct;
import lombok.RequiredArgsConstructor;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

// The parts and labor lines under each maintenance record, as on the GSO's Repair and Maintenance
// Card. When a record has lines, its cost (the card's "Cost of Repair") is their sum.
@Service
@RequiredArgsConstructor
public class MaintenanceItemService {

    private static final int MAX_LINES = 100;

    private final JdbcTemplate jdbcTemplate;

    // Created here rather than in a migration script, like the transfer tables, so a hosted
    // database gets it on the next deploy.
    @PostConstruct
    void ensureTable() {
        jdbcTemplate.execute("""
            CREATE TABLE IF NOT EXISTS maintenance_items (
              item_id        INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
              maintenance_id INT NOT NULL,
              line_no        INT NOT NULL,
              kind           VARCHAR(10) NOT NULL,
              particular     VARCHAR(255) NOT NULL,
              unit           VARCHAR(30) NULL,
              quantity       DECIMAL(12,2) NULL,
              unit_cost      DECIMAL(15,2) NULL,
              total_cost     DECIMAL(15,2) NOT NULL,
              additional     TINYINT(1) NOT NULL DEFAULT 0,
              KEY idx_maint_items_record (maintenance_id)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci
            """);
        Integer has = jdbcTemplate.queryForObject("""
            SELECT COUNT(*) FROM information_schema.COLUMNS
            WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'maintenance_items' AND COLUMN_NAME = 'additional'
            """, Integer.class);
        if (has == null || has == 0) {
            jdbcTemplate.execute("ALTER TABLE maintenance_items ADD COLUMN additional TINYINT(1) NOT NULL DEFAULT 0");
        }
    }

    // Checks and tidies the lines from a form; a part's total is always quantity x unit cost.
    public List<MaintenanceItem> clean(List<MaintenanceItem> items) {
        if (items == null) return null;
        if (items.size() > MAX_LINES) throw new IllegalArgumentException("A record can have up to " + MAX_LINES + " parts and labor lines.");
        List<MaintenanceItem> out = new ArrayList<>();
        for (int i = 0; i < items.size(); i++) {
            MaintenanceItem it = items.get(i);
            String where = "Line " + (i + 1) + ": ";
            String particular = it.particular() == null ? "" : it.particular().trim();
            if (particular.isEmpty()) throw new IllegalArgumentException(where + "enter the particular.");
            if (particular.length() > 255) throw new IllegalArgumentException(where + "the particular is too long (255 characters max).");
            if ("LABOR".equalsIgnoreCase(it.kind())) {
                BigDecimal cost = money(it.totalCost(), where + "enter the labor cost.");
                out.add(new MaintenanceItem(it.id(), "LABOR", particular, null, null, null, cost, false));
            } else {
                BigDecimal qty = it.quantity();
                if (qty == null || qty.signum() <= 0) throw new IllegalArgumentException(where + "the quantity must be more than 0.");
                BigDecimal unitCost = money(it.unitCost(), where + "enter the unit cost.");
                String unit = it.unit() == null || it.unit().isBlank() ? null : it.unit().trim();
                if (unit != null && unit.length() > 30) throw new IllegalArgumentException(where + "the unit is too long (30 characters max).");
                out.add(new MaintenanceItem(it.id(), "PART", particular, unit, qty.setScale(2, RoundingMode.HALF_UP), unitCost,
                    qty.multiply(unitCost).setScale(2, RoundingMode.HALF_UP), Boolean.TRUE.equals(it.additional())));
            }
        }
        return out;
    }

    private static BigDecimal money(BigDecimal v, String missing) {
        if (v == null) throw new IllegalArgumentException(missing);
        if (v.signum() < 0) throw new IllegalArgumentException(missing.replace("enter", "use a positive"));
        return v.setScale(2, RoundingMode.HALF_UP);
    }

    public static BigDecimal total(List<MaintenanceItem> items) {
        return items.stream().map(MaintenanceItem::totalCost).reduce(BigDecimal.ZERO, BigDecimal::add);
    }

    // Saves the record's lines. A line sent with the id of one of the record's saved lines updates it
    // (so its photos stay with it); the others are added, and saved lines not sent are removed.
    // Returns the ids of the removed lines, whose photos the caller removes.
    public List<Long> replace(Long maintenanceId, List<MaintenanceItem> items) {
        Set<Long> saved = new HashSet<>(jdbcTemplate.queryForList(
            "SELECT item_id FROM maintenance_items WHERE maintenance_id = ?", Long.class, maintenanceId));
        Set<Long> kept = new HashSet<>();
        for (int i = 0; i < items.size(); i++) {
            MaintenanceItem it = items.get(i);
            boolean additional = Boolean.TRUE.equals(it.additional());
            if (it.id() != null && saved.contains(it.id()) && kept.add(it.id())) {
                jdbcTemplate.update("""
                    UPDATE maintenance_items SET line_no = ?, kind = ?, particular = ?, unit = ?, quantity = ?, unit_cost = ?,
                      total_cost = ?, additional = ? WHERE item_id = ?
                    """, i + 1, it.kind(), it.particular(), it.unit(), it.quantity(), it.unitCost(), it.totalCost(), additional, it.id());
            } else {
                jdbcTemplate.update("""
                    INSERT INTO maintenance_items (maintenance_id, line_no, kind, particular, unit, quantity, unit_cost, total_cost, additional)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """, maintenanceId, i + 1, it.kind(), it.particular(), it.unit(), it.quantity(), it.unitCost(), it.totalCost(), additional);
            }
        }
        List<Long> removed = saved.stream().filter(id -> !kept.contains(id)).toList();
        for (Long id : removed) jdbcTemplate.update("DELETE FROM maintenance_items WHERE item_id = ?", id);
        return removed;
    }

    public List<MaintenanceItem> forRecord(Long maintenanceId) {
        return byRecord(List.of(maintenanceId)).getOrDefault(maintenanceId, List.of());
    }

    // Puts each record's lines on it (an empty list when it has none).
    public <T extends Iterable<MaintenanceLedger>> T attach(T records) {
        List<Long> ids = new ArrayList<>();
        records.forEach(r -> ids.add(r.getId()));
        Map<Long, List<MaintenanceItem>> lines = byRecord(ids);
        records.forEach(r -> r.setItems(lines.getOrDefault(r.getId(), List.of())));
        return records;
    }

    private Map<Long, List<MaintenanceItem>> byRecord(List<Long> ids) {
        Map<Long, List<MaintenanceItem>> out = new LinkedHashMap<>();
        if (ids.isEmpty()) return out;
        String marks = String.join(", ", Collections.nCopies(ids.size(), "?"));
        jdbcTemplate.query("SELECT * FROM maintenance_items WHERE maintenance_id IN (" + marks + ") ORDER BY maintenance_id, line_no",
            rs -> {
                out.computeIfAbsent(rs.getLong("maintenance_id"), k -> new ArrayList<>()).add(new MaintenanceItem(
                    rs.getLong("item_id"), rs.getString("kind"), rs.getString("particular"), rs.getString("unit"),
                    rs.getBigDecimal("quantity"), rs.getBigDecimal("unit_cost"), rs.getBigDecimal("total_cost"),
                    rs.getBoolean("additional")));
            }, ids.toArray());
        return out;
    }
}
