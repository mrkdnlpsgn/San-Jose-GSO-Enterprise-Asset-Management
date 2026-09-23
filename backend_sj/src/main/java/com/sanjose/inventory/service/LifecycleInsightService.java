package com.sanjose.inventory.service;

import com.google.genai.Client;
import com.google.genai.errors.ApiException;
import com.google.genai.types.Content;
import com.google.genai.types.GenerateContentConfig;
import com.google.genai.types.GenerateContentResponse;
import com.google.genai.types.Part;
import com.sanjose.inventory.config.GeminiConfig;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

// How many assets were maintained / disposed over a period (last day, 7 days, 30 days or
// 12 months), compared with the period before, broken down by type/method, status, category
// and office, plus a day- or month-bucketed series. The numbers come straight from the
// ledgers; Gemini is only asked (on demand) to turn them into a short plain-language summary.
// Counts use the event date (maintenance_date / inspection_date) of approved, non-deleted
// records, and are limited to the caller's office for STAFF (see AccessService).
@Slf4j
@Service
@RequiredArgsConstructor
public class LifecycleInsightService {

    private static final String MODEL = "gemini-2.5-flash";

    private final JdbcTemplate jdbcTemplate;
    private final GeminiConfig geminiConfig;

    public enum Range {
        DAY(1, "Today"), WEEK(7, "Last 7 days"), MONTH(30, "Last 30 days"), YEAR(365, "Last 12 months");
        final int days; final String label;
        Range(int days, String label) { this.days = days; this.label = label; }

        public static Range parse(String s) {
            if (s == null || s.isBlank()) return MONTH;
            try { return valueOf(s.trim().toUpperCase()); }
            catch (IllegalArgumentException e) { throw new IllegalArgumentException("Unknown range: " + s + " (use day, week, month or year)"); }
        }
    }

    public Map<String, Object> stats(Range range, Long officeId) {
        LocalDate end = LocalDate.now();                       // inclusive
        LocalDate start = end.minusDays(range.days - 1L);
        LocalDate prevEnd = start.minusDays(1);
        LocalDate prevStart = prevEnd.minusDays(range.days - 1L);

        Map<String, Object> out = new LinkedHashMap<>();
        out.put("range", range.name());
        out.put("label", range.label);
        out.put("from", start.toString());
        out.put("to", end.toString());
        out.put("scope", officeId == null ? "ALL_OFFICES" : officeName(officeId));
        out.put("maintenance", ledger(Ledger.MAINTENANCE, start, end, prevStart, prevEnd, officeId, range));
        out.put("disposal", ledger(Ledger.DISPOSAL, start, end, prevStart, prevEnd, officeId, range));
        return out;
    }

    public Map<String, Object> summarize(Range range, Long officeId) {
        geminiConfig.requireConfigured();
        Map<String, Object> stats = stats(range, officeId);
        Map<String, Object> out = new LinkedHashMap<>(stats);
        out.put("summary", requestSummary(stats));
        return out;
    }

    // ---- aggregation ---------------------------------------------------------------

    private enum Ledger {
        MAINTENANCE("maintenance_ledger", "maintenance_date", "maintenance_type", "`status`", "cost"),
        DISPOSAL("disposal_ledger", "inspection_date", "recommended_method", "disposal_status", "amount");
        final String table, date, kind, status, money;
        Ledger(String table, String date, String kind, String status, String money) {
            this.table = table; this.date = date; this.kind = kind; this.status = status; this.money = money;
        }
    }

    private Map<String, Object> ledger(Ledger l, LocalDate start, LocalDate end, LocalDate prevStart, LocalDate prevEnd,
                                       Long officeId, Range range) {
        String from = " FROM " + l.table + " x JOIN assets a ON a.asset_id = x.asset_id"
            + " LEFT JOIN categories c ON c.category_id = a.category_id"
            + " LEFT JOIN offices o ON o.office_id = a.office_id"
            + " WHERE x.is_deleted = FALSE AND x.approval_status = 'APPROVED'"
            + " AND x." + l.date + " BETWEEN ? AND ?"
            + (officeId != null ? " AND a.office_id = ?" : "");
        Object[] cur = officeId != null ? new Object[]{ start, end, officeId } : new Object[]{ start, end };
        Object[] prev = officeId != null ? new Object[]{ prevStart, prevEnd, officeId } : new Object[]{ prevStart, prevEnd };

        Map<String, Object> m = new LinkedHashMap<>();
        Map<String, Object> totals = jdbcTemplate.queryForMap(
            "SELECT COUNT(*) AS records, COUNT(DISTINCT x.asset_id) AS assets, COALESCE(SUM(x." + l.money + "), 0) AS money" + from, cur);
        Map<String, Object> before = jdbcTemplate.queryForMap(
            "SELECT COUNT(*) AS records, COUNT(DISTINCT x.asset_id) AS assets" + from, prev);
        m.put("records", ((Number) totals.get("records")).longValue());
        m.put("assets", ((Number) totals.get("assets")).longValue());
        m.put(l == Ledger.MAINTENANCE ? "totalCost" : "totalProceeds", toMoney(totals.get("money")));
        m.put("previousRecords", ((Number) before.get("records")).longValue());
        m.put("previousAssets", ((Number) before.get("assets")).longValue());
        m.put(l == Ledger.MAINTENANCE ? "byType" : "byMethod", countBy("x." + l.kind, from, cur, 10));
        m.put("byStatus", countBy("x." + l.status, from, cur, 10));
        m.put("topCategories", countBy("COALESCE(c.category_name, 'Uncategorized')", from, cur, 5));
        if (officeId == null) m.put("topOffices", countBy("COALESCE(o.office_name, 'Unassigned')", from, cur, 5));
        m.put("series", series(l, from, cur, start, end, range));

        String pendingSql = "SELECT COUNT(*) FROM " + l.table + " x JOIN assets a ON a.asset_id = x.asset_id"
            + " WHERE x.is_deleted = FALSE AND x.approval_status = 'PENDING_APPROVAL'"
            + (officeId != null ? " AND a.office_id = ?" : "");
        m.put("pendingRequests", officeId != null
            ? jdbcTemplate.queryForObject(pendingSql, Long.class, officeId)
            : jdbcTemplate.queryForObject(pendingSql, Long.class));
        return m;
    }

    private List<Map<String, Object>> countBy(String expr, String from, Object[] args, int limit) {
        return jdbcTemplate.query(
            "SELECT " + expr + " AS label, COUNT(DISTINCT x.asset_id) AS assets" + from
                + " GROUP BY label ORDER BY assets DESC, label LIMIT " + limit,
            (rs, rn) -> {
                Map<String, Object> row = new LinkedHashMap<>();
                row.put("label", rs.getString("label"));
                row.put("assets", rs.getLong("assets"));
                return row;
            }, args);
    }

    // One point per day (up to 30 days) or per month (year view), zero-filled.
    private List<Map<String, Object>> series(Ledger l, String from, Object[] args, LocalDate start, LocalDate end, Range range) {
        boolean monthly = range == Range.YEAR;
        String bucketExpr = monthly ? "DATE_FORMAT(x." + l.date + ", '%Y-%m')" : "DATE_FORMAT(x." + l.date + ", '%Y-%m-%d')";
        Map<String, Long> counts = new LinkedHashMap<>();
        jdbcTemplate.query("SELECT " + bucketExpr + " AS bucket, COUNT(DISTINCT x.asset_id) AS assets" + from + " GROUP BY bucket",
            rs -> { counts.put(rs.getString("bucket"), rs.getLong("assets")); }, args);

        List<Map<String, Object>> points = new ArrayList<>();
        DateTimeFormatter fmt = DateTimeFormatter.ofPattern(monthly ? "yyyy-MM" : "yyyy-MM-dd");
        LocalDate cursor = monthly ? start.withDayOfMonth(1) : start;
        while (!cursor.isAfter(end)) {
            String key = cursor.format(fmt);
            Map<String, Object> p = new LinkedHashMap<>();
            p.put("bucket", key);
            p.put("assets", counts.getOrDefault(key, 0L));
            points.add(p);
            cursor = monthly ? cursor.plusMonths(1) : cursor.plusDays(1);
        }
        return points;
    }

    private String officeName(Long officeId) {
        List<String> names = jdbcTemplate.queryForList("SELECT office_name FROM offices WHERE office_id = ?", String.class, officeId);
        return names.isEmpty() ? "No office assigned" : names.get(0);
    }

    private static BigDecimal toMoney(Object v) {
        return v instanceof BigDecimal b ? b : new BigDecimal(String.valueOf(v));
    }

    // ---- AI summary ------------------------------------------------------------------

    private static final String SYSTEM_PROMPT = """
        You write a short plain-English summary for the General Services Office of a Philippine \
        municipal government, describing how many ICT and other government assets were maintained \
        and disposed of during a reporting period. You are given pre-computed statistics (JSON) — use \
        only those numbers, never invent figures. In 3-5 short sentences: state how many assets were \
        maintained and how many disposed of, compare each with the previous period of the same length \
        (say whether it went up, down or stayed the same), point out the busiest period in the series \
        and the categories/offices that account for most of the activity, and mention pending requests \
        if any are waiting for approval. Money is in Philippine pesos (write it as PHP). If a period has \
        no activity, say so plainly. Plain text only, no markdown, no bullet points, no headers.""";

    private String requestSummary(Map<String, Object> stats) {
        Client client = geminiConfig.buildClient();
        String prompt = "Reporting period statistics:\n" + toJson(stats);
        GenerateContentConfig config = GenerateContentConfig.builder()
            .systemInstruction(Content.fromParts(Part.fromText(SYSTEM_PROMPT)))
            .build();
        GenerateContentResponse response;
        try {
            response = client.models.generateContent(MODEL, prompt, config);
        } catch (ApiException e) {
            log.error("Lifecycle summary request failed: {}", e.getMessage());
            throw new IllegalStateException("AI summary request failed: " + e.getMessage(), e);
        }
        String text = response.text();
        if (text == null || text.isBlank()) throw new IllegalStateException("The AI did not return a summary.");
        return text.trim();
    }

    // Small hand-rolled JSON writer — the stats are only maps, lists, strings and numbers.
    private static String toJson(Object v) {
        if (v == null) return "null";
        if (v instanceof Map<?, ?> m) {
            return m.entrySet().stream()
                .map(e -> toJson(String.valueOf(e.getKey())) + ":" + toJson(e.getValue()))
                .collect(Collectors.joining(",", "{", "}"));
        }
        if (v instanceof List<?> list) return list.stream().map(LifecycleInsightService::toJson).collect(Collectors.joining(",", "[", "]"));
        if (v instanceof Number) return v.toString();
        return "\"" + String.valueOf(v).replace("\\", "\\\\").replace("\"", "\\\"") + "\"";
    }
}
