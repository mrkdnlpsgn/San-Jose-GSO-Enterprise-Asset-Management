package com.sanjose.inventory.service;

import com.google.genai.Client;
import com.google.genai.types.Content;
import com.google.genai.types.GenerateContentConfig;
import com.google.genai.types.GenerateContentResponse;
import com.google.genai.types.Part;
import com.sanjose.inventory.config.AppTime;
import com.sanjose.inventory.config.GeminiConfig;
import com.sanjose.inventory.config.SpHelper;
import com.sanjose.inventory.entity.AuditLogDigest;
import lombok.extern.slf4j.Slf4j;
import org.springframework.dao.DataAccessException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.sql.Date;
import java.sql.Timestamp;
import java.time.LocalDate;
import java.util.List;
import java.util.Map;
import java.util.Optional;

// The dashboard's "AI Asset Health" card (admin). Kept under its original name, endpoint
// (/api/audit-logs/digest) and table (audit_log_digests) so existing clients keep working;
// it used to summarize recent audit-log activity, and now summarizes the condition of the
// inventory itself: counts from the live tables, written up by Gemini in plain words for
// GSO staff and admins. covered_entries now holds the number of in-use assets covered.
@Slf4j
@Service
@Transactional
public class AuditLogDigestService {

    // Assets still in service: not deleted, not disposed or archived.
    private static final String IN_USE = "a.is_deleted = 0 AND a.lifecycle_status NOT IN ('DISPOSED','ARCHIVED')";
    // Older ledger rows predate approvals (NULL) and count as approved.
    private static final String APPROVED = "COALESCE(%s.approval_status, 'APPROVED') = 'APPROVED'";

    private final JdbcTemplate jdbcTemplate;
    private final GeminiConfig geminiConfig;

    public AuditLogDigestService(JdbcTemplate jdbcTemplate, GeminiConfig geminiConfig) {
        this.jdbcTemplate = jdbcTemplate;
        this.geminiConfig = geminiConfig;
    }

    private static final RowMapper<AuditLogDigest> MAPPER = (rs, rn) -> {
        AuditLogDigest d = new AuditLogDigest();
        d.setId(rs.getLong("id"));
        d.setDigest(rs.getString("digest"));
        d.setCoveredEntries(rs.getInt("covered_entries"));
        Timestamp genAt = rs.getTimestamp("generated_at");
        d.setGeneratedAt(genAt != null ? genAt.toLocalDateTime() : null);
        d.setGeneratedBySystem(rs.getBoolean("generated_by_system"));
        return d;
    };

    public Optional<AuditLogDigest> getLatest() {
        List<AuditLogDigest> list = jdbcTemplate.query("CALL sp_audit_log_digests_get_latest()", MAPPER);
        return list.isEmpty() ? Optional.empty() : Optional.of(list.get(0));
    }

    public AuditLogDigest generate() {
        geminiConfig.requireConfigured();

        int inUse = count("SELECT COUNT(*) FROM assets a WHERE " + IN_USE);
        if (inUse == 0) {
            throw new IllegalStateException("There are no assets in use to report on yet.");
        }

        String text = requestInsights(healthFacts(inUse));

        Long newId = SpHelper.callWithOutLong(jdbcTemplate,
            "CALL sp_audit_log_digests_create(?, ?, ?)", text, inUse);

        return getLatest()
            .filter(d -> d.getId().equals(newId))
            .orElseThrow(() -> new IllegalStateException("Insights were saved but could not be re-fetched"));
    }

    // ── the numbers ────────────────────────────────────────────────────────────

    private int count(String sql, Object... args) {
        Integer n = jdbcTemplate.queryForObject(sql, Integer.class, args);
        return n != null ? n : 0;
    }

    // "MTO: 12, GSO: 7" - the top few rows of a name/count query; "none" when empty.
    private String top(String sql) {
        List<Map<String, Object>> rows = jdbcTemplate.queryForList(sql);
        if (rows.isEmpty()) return "none";
        StringBuilder sb = new StringBuilder();
        for (Map<String, Object> r : rows) {
            if (!sb.isEmpty()) sb.append(", ");
            sb.append(r.get("name")).append(": ").append(r.get("n"));
        }
        return sb.toString();
    }

    private static String pct(int part, int whole) {
        return whole == 0 ? "0%" : Math.round(part * 100.0 / whole) + "%";
    }

    // Plain lines of facts; the AI may only use these.
    private String healthFacts(int inUse) {
        Date today = Date.valueOf(AppTime.today());
        Date yearAgo = Date.valueOf(AppTime.today().minusYears(1));

        int good = count("SELECT COUNT(*) FROM assets a WHERE " + IN_USE + " AND a.`condition` IN ('NEW','GOOD','SERVICEABLE')");
        int needsRepair = count("SELECT COUNT(*) FROM assets a WHERE " + IN_USE + " AND a.`condition` = 'REPAIRABLE'");
        int broken = count("SELECT COUNT(*) FROM assets a WHERE " + IN_USE + " AND a.`condition` = 'UNSERVICEABLE'");
        int inRepair = count("SELECT COUNT(*) FROM assets a WHERE " + IN_USE + " AND a.lifecycle_status = 'UNDER_MAINTENANCE'");
        int pastLife = count("""
            SELECT COUNT(*) FROM assets a JOIN categories c ON c.category_id = a.category_id
            WHERE %s AND c.useful_life_years IS NOT NULL AND a.acquisition_date IS NOT NULL
              AND DATE_ADD(a.acquisition_date, INTERVAL c.useful_life_years YEAR) < ?""".formatted(IN_USE), today);

        int openWork = count("SELECT COUNT(*) FROM maintenance_ledger m WHERE m.is_deleted = 0 AND "
            + APPROVED.formatted("m") + " AND m.status IN ('SCHEDULED','ONGOING')");
        int disposalsOpen = count("SELECT COUNT(*) FROM disposal_ledger d WHERE d.is_deleted = 0 AND "
            + APPROVED.formatted("d") + " AND d.disposal_status IN ('PENDING','APPROVED')");
        BigDecimal repairSpend = jdbcTemplate.queryForObject(
            "SELECT COALESCE(SUM(m.cost), 0) FROM maintenance_ledger m WHERE m.is_deleted = 0 AND "
                + APPROVED.formatted("m") + " AND m.maintenance_date >= ?", BigDecimal.class, yearAgo);

        int pendingMaint = count("SELECT COUNT(*) FROM maintenance_ledger WHERE is_deleted = 0 AND approval_status = 'PENDING_APPROVAL'");
        int pendingDisp = count("SELECT COUNT(*) FROM disposal_ledger WHERE is_deleted = 0 AND approval_status = 'PENDING_APPROVAL'");
        int pendingTransfers;
        try {
            pendingTransfers = count("SELECT COUNT(*) FROM asset_transfer_requests WHERE status = 'PENDING_APPROVAL'");
        } catch (DataAccessException e) {
            pendingTransfers = 0; // table not created yet on this database
        }

        String problemOffices = top("""
            SELECT o.office_name AS name, COUNT(*) AS n FROM assets a JOIN offices o ON o.office_id = a.office_id
            WHERE %s AND a.`condition` IN ('REPAIRABLE','UNSERVICEABLE')
            GROUP BY o.office_name ORDER BY n DESC LIMIT 3""".formatted(IN_USE));
        String problemCategories = top("""
            SELECT c.category_name AS name, COUNT(*) AS n FROM assets a JOIN categories c ON c.category_id = a.category_id
            WHERE %s AND a.`condition` IN ('REPAIRABLE','UNSERVICEABLE')
            GROUP BY c.category_name ORDER BY n DESC LIMIT 3""".formatted(IN_USE));
        // each asset's latest AI recommendation
        String aiAdvice = top("""
            SELECT r.recommendation AS name, COUNT(*) AS n FROM ai_recommendations r
            JOIN (SELECT asset_id, MAX(recommendation_id) AS id FROM ai_recommendations GROUP BY asset_id) last
              ON last.id = r.recommendation_id
            JOIN assets a ON a.asset_id = r.asset_id
            WHERE %s AND r.recommendation IN ('REVIEW_FOR_DISPOSAL','BUDGET_PRIORITY','REPAIR')
            GROUP BY r.recommendation ORDER BY n DESC""".formatted(IN_USE));

        return """
            Assets in use: %d
            Good condition (serviceable): %d (%s)
            Needs repair (repairable): %d
            Broken, beyond repair (unserviceable): %d
            Currently being repaired: %d
            Past their expected useful life: %d
            Open maintenance jobs (scheduled or ongoing): %d
            Disposals in progress: %d
            Repair spending in the last 12 months: PHP %,.2f
            Staff requests waiting for admin approval: maintenance %d, disposal %d, transfer %d
            Offices with the most assets needing repair or broken: %s
            Categories with the most assets needing repair or broken: %s
            AI per-asset advice (latest per asset): %s
            Today (Philippines): %s""".formatted(
                inUse, good, pct(good, inUse), needsRepair, broken, inRepair, pastLife,
                openWork, disposalsOpen, repairSpend != null ? repairSpend : BigDecimal.ZERO,
                pendingMaint, pendingDisp, pendingTransfers,
                problemOffices, problemCategories, aiAdvice, LocalDate.now(AppTime.ZONE));
    }

    // ── the write-up ───────────────────────────────────────────────────────────

    private static final String SYSTEM_PROMPT = """
        You write the "Asset Health" note on the dashboard of the General Services Office (GSO) of the \
        Municipality of San Jose, Batangas. The readers are GSO staff and administrators, not technical people.

        Use ONLY the facts given. Never invent numbers, names, causes or dates.

        Format, plain text:
        - First line: one short sentence on overall health with the key number, e.g. \
        "Most assets are in good shape: 2,180 of 2,417 (90%) are working well."
        - Then 2 or 3 lines, each starting with "• ", each one specific thing to do, with its number and \
        the office or category when given, e.g. "• Approve 3 staff repair requests." or \
        "• 12 broken items in MTO. Start their disposal."
        - Pick the lines in this order of urgency, skipping what is zero: broken items; items that need \
        repair (name the office with the most); items past their expected life (plan replacement); staff \
        requests waiting for approval; AI advice to review for disposal or budget.
        - Each action must say exactly what to do ("schedule repair", "plan replacement in next year's \
        budget", "approve or reject"). Never use vague verbs like "handle", "address", "continue" or "monitor".
        - If nothing needs action, the second line is "• Nothing needs action right now."

        Rules: at most 60 words in total. Everyday words: say "working well" not "serviceable", "needs \
        repair" not "repairable", "broken" not "unserviceable", "old" or "past its expected life" not \
        "depreciated". Skip anything that is zero. Use the peso sign (₱) for money. No headings, no \
        markdown other than the "• " bullets, no closing remarks.""";

    private String requestInsights(String facts) {
        Client client = geminiConfig.buildClient();

        GenerateContentConfig config = GenerateContentConfig.builder()
            .thinkingConfig(GeminiConfig.thinking(GeminiConfig.NO_THINKING))
            .systemInstruction(Content.fromParts(Part.fromText(SYSTEM_PROMPT)))
            .build();

        GenerateContentResponse response = geminiConfig.generate(
            client, GeminiConfig.Tier.FAST, "AI asset health request", "Facts:\n" + facts, config);

        String text = response.text();
        if (text == null || text.isBlank()) {
            throw new IllegalStateException("The AI did not return any insights.");
        }
        return text.trim();
    }
}
