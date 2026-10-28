package com.sanjose.inventory.service;

import lombok.RequiredArgsConstructor;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;

import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

// Everything the web dashboard shows about assets, worked out in the database so the browser no
// longer downloads every asset, maintenance and disposal record to count them. Staff see only
// their own assets (AccessService.StaffScope), as everywhere else.
//
// "In use" leaves out archived assets and assets whose disposal is finished, so the totals,
// value and charts describe property the municipality still holds.
@Service
@RequiredArgsConstructor
public class DashboardService {

    private final JdbcTemplate jdbcTemplate;

    // On hand: everything except archived assets and those whose disposal is completed. An asset
    // marked DISPOSED with its disposal still pending is still here (and still on the books).
    // Also used by ReplacementForecastService and DepreciationService so their totals match Home.
    static final String IN_USE =
        " a.is_deleted = 0 AND a.lifecycle_status <> 'ARCHIVED'"
        + " AND NOT (a.lifecycle_status = 'DISPOSED' AND EXISTS (SELECT 1 FROM disposal_ledger d"
        + "   WHERE d.asset_id = a.asset_id AND d.is_deleted = 0 AND d.approval_status <> 'REJECTED' AND d.disposal_status = 'COMPLETED'))";

    // under maintenance and the repair not finished: an open record, or no record at all
    private static final String UNDER_REPAIR =
        "a.lifecycle_status = 'UNDER_MAINTENANCE' AND (EXISTS (SELECT 1 FROM maintenance_ledger m"
        + "   WHERE m.asset_id = a.asset_id AND m.is_deleted = 0 AND m.approval_status <> 'REJECTED' AND m.status <> 'COMPLETED')"
        + " OR NOT EXISTS (SELECT 1 FROM maintenance_ledger m"
        + "   WHERE m.asset_id = a.asset_id AND m.is_deleted = 0 AND m.approval_status <> 'REJECTED'))";

    private static final String NO_DISPOSAL_RECORD =
        "a.`condition` = 'UNSERVICEABLE' AND NOT EXISTS (SELECT 1 FROM disposal_ledger d"
        + "   WHERE d.asset_id = a.asset_id AND d.is_deleted = 0 AND d.approval_status <> 'REJECTED')";

    private static final int ATTENTION_ITEMS = 10;

    public Map<String, Object> summary(AccessService.StaffScope scope) {
        String where = IN_USE + (scope != null ? " AND " + scope.sql("a") : "");
        Object[] args = scope != null ? scope.args() : new Object[0];

        Map<String, Object> out = new LinkedHashMap<>();
        jdbcTemplate.query(
            "SELECT COUNT(*) total, COALESCE(SUM(a.unit_value * COALESCE(a.quantity, 1)), 0) total_value,"
            + " COALESCE(SUM(DATE_FORMAT(CONVERT_TZ(a.created_at, '+00:00', '+08:00'), '%Y-%m')"
            + "   = DATE_FORMAT(CONVERT_TZ(UTC_TIMESTAMP(), '+00:00', '+08:00'), '%Y-%m')), 0) new_this_month,"
            + " COALESCE(SUM(" + UNDER_REPAIR + "), 0) under_repair,"
            + " COALESCE(SUM(a.lifecycle_status = 'DISPOSED'), 0) for_disposal,"
            + " COALESCE(SUM(a.`condition` = 'NEW'), 0) is_new,"
            + " COALESCE(SUM(a.`condition` = 'GOOD'), 0) good,"
            + " COALESCE(SUM(a.`condition` = 'SERVICEABLE'), 0) serviceable,"
            + " COALESCE(SUM(a.`condition` = 'REPAIRABLE'), 0) repairable,"
            + " COALESCE(SUM(a.`condition` = 'UNSERVICEABLE'), 0) unserviceable"
            + " FROM assets a WHERE" + where,
            rs -> {
                out.put("inUse", rs.getLong("total"));
                out.put("totalValue", rs.getBigDecimal("total_value") != null ? rs.getBigDecimal("total_value") : BigDecimal.ZERO);
                out.put("newThisMonth", rs.getLong("new_this_month"));
                out.put("underRepair", rs.getLong("under_repair"));
                out.put("forDisposal", rs.getLong("for_disposal"));
                Map<String, Long> condition = new LinkedHashMap<>();
                condition.put("NEW", rs.getLong("is_new"));
                condition.put("GOOD", rs.getLong("good"));
                condition.put("SERVICEABLE", rs.getLong("serviceable"));
                condition.put("REPAIRABLE", rs.getLong("repairable"));
                condition.put("UNSERVICEABLE", rs.getLong("unserviceable"));
                out.put("condition", condition);
            }, args);

        out.put("offices", jdbcTemplate.query(
            "SELECT a.office_id id, COALESCE(o.office_name, 'Unassigned') name, COUNT(*) n"
            + " FROM assets a LEFT JOIN offices o ON o.office_id = a.office_id WHERE" + where
            + " GROUP BY a.office_id, o.office_name ORDER BY n DESC, name",
            (rs, i) -> group("officeId", rs.getObject("id", Long.class), "office", rs.getString("name"), rs.getLong("n")), args));

        out.put("categories", jdbcTemplate.query(
            "SELECT a.category_id id, COALESCE(c.category_name, 'Uncategorized') name, COUNT(*) n"
            + " FROM assets a LEFT JOIN categories c ON c.category_id = a.category_id WHERE" + where
            + " GROUP BY a.category_id, c.category_name ORDER BY n DESC, name",
            (rs, i) -> group("categoryId", rs.getObject("id", Long.class), "category", rs.getString("name"), rs.getLong("n")), args));

        Map<String, Object> attention = new LinkedHashMap<>();
        attention.put("unserviceableNoDisposal", attention(where, NO_DISPOSAL_RECORD, args));
        attention.put("noAccountable", attention(where, "a.personnel_id IS NULL", args));
        attention.put("noOffice", attention(where, "a.office_id IS NULL", args));
        out.put("attention", attention);
        return out;
    }

    private static Map<String, Object> group(String idKey, Long id, String nameKey, String name, long count) {
        Map<String, Object> g = new LinkedHashMap<>();
        g.put(idKey, id);
        g.put(nameKey, name);
        g.put("count", count);
        return g;
    }

    // How many in-use assets match, the first few of them (to list in the notification), and the
    // ids of all of them, so the Assets page can highlight every one when the notification is opened.
    private Map<String, Object> attention(String where, String condition, Object[] args) {
        String filter = " FROM assets a WHERE" + where + " AND (" + condition + ")";
        Long count = jdbcTemplate.queryForObject("SELECT COUNT(*)" + filter, Long.class, args);
        List<Object> withLimit = new ArrayList<>(List.of(args));
        withLimit.add(ATTENTION_ITEMS);
        List<Map<String, Object>> items = jdbcTemplate.query(
            "SELECT a.asset_id, a.property_number, a.description" + filter + " ORDER BY a.property_number LIMIT ?",
            (rs, i) -> {
                Map<String, Object> m = new LinkedHashMap<>();
                m.put("id", rs.getLong("asset_id"));
                m.put("propertyNumber", rs.getString("property_number"));
                m.put("description", rs.getString("description"));
                return m;
            }, withLimit.toArray());
        List<Long> ids = jdbcTemplate.queryForList("SELECT a.asset_id" + filter, Long.class, args);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("count", count != null ? count : 0L);
        out.put("items", items);
        out.put("ids", ids);
        return out;
    }
}
