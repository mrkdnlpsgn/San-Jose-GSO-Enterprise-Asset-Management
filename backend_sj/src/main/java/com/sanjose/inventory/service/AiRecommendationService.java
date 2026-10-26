package com.sanjose.inventory.service;

import com.sanjose.inventory.config.AppTime;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.google.genai.Client;
import com.google.genai.types.Content;
import com.google.genai.types.GenerateContentConfig;
import com.google.genai.types.GenerateContentResponse;
import com.google.genai.types.Part;
import com.google.genai.types.Schema;
import com.google.genai.types.Type;
import com.sanjose.inventory.config.GeminiConfig;
import com.sanjose.inventory.config.SpHelper;
import com.sanjose.inventory.dto.AiRecommendationSummaryItem;
import com.sanjose.inventory.dto.AssetLifecycleAdvice;
import com.sanjose.inventory.entity.AiRecommendation;
import com.sanjose.inventory.entity.Asset;
import lombok.extern.slf4j.Slf4j;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.sql.Timestamp;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.temporal.ChronoUnit;
import java.util.Arrays;
import java.util.List;
import java.util.Map;
import java.util.Optional;

@Slf4j
@Service
@Transactional
public class AiRecommendationService {

    private static final ObjectMapper OBJECT_MAPPER = new ObjectMapper();

    private final JdbcTemplate jdbcTemplate;
    private final AssetService assetService;
    private final AuditLogService auditLogService;
    private final GeminiConfig geminiConfig;

    public AiRecommendationService(JdbcTemplate jdbcTemplate, AssetService assetService,
                                    AuditLogService auditLogService, GeminiConfig geminiConfig) {
        this.jdbcTemplate = jdbcTemplate;
        this.assetService = assetService;
        this.auditLogService = auditLogService;
        this.geminiConfig = geminiConfig;
    }

    private static final RowMapper<AiRecommendation> RECOMMENDATION_MAPPER = (rs, rn) -> {
        AiRecommendation r = new AiRecommendation();
        r.setId(rs.getLong("id"));
        r.setAssetAgeYears(rs.getBigDecimal("asset_age_years"));
        r.setTotalRepairCost(rs.getBigDecimal("total_repair_cost"));
        r.setRepairFrequency(rs.getObject("repair_frequency", Integer.class));
        r.setConditionScore(rs.getObject("condition_score", Integer.class));
        r.setRecommendation(AiRecommendation.Recommendation.valueOf(rs.getString("recommendation")));
        r.setRationale(rs.getString("rationale"));
        Timestamp genAt = rs.getTimestamp("generated_at");
        r.setGeneratedAt(genAt != null ? genAt.toLocalDateTime() : null);
        r.setGeneratedBySystem(rs.getBoolean("generated_by_system"));

        Long assetId = rs.getObject("asset_id", Long.class);
        if (assetId != null) {
            Asset a = new Asset();
            a.setId(assetId);
            a.setPropertyNumber(rs.getString("asset_propertyNumber"));
            a.setParNumber(rs.getString("asset_parNumber"));
            a.setDescription(rs.getString("asset_description"));
            r.setAsset(a);
        }
        return r;
    };

    public Optional<AiRecommendation> getLatest(Long assetId) {
        List<AiRecommendation> list = jdbcTemplate.query(
            "CALL sp_ai_recommendations_get_latest_by_asset(?)", RECOMMENDATION_MAPPER, assetId);
        return list.isEmpty() ? Optional.empty() : Optional.of(list.get(0));
    }

    // scope null = every asset (admin). Staff: the same count as sp_ai_recommendations_summary,
    // over only their own assets (see AccessService).
    public List<AiRecommendationSummaryItem> getSummary(AccessService.StaffScope scope) {
        String sql = scope == null ? "CALL sp_ai_recommendations_summary()" : """
            SELECT r.recommendation, COUNT(*) AS cnt
            FROM ai_recommendations r
            INNER JOIN (
                SELECT asset_id, MAX(recommendation_id) AS latest_id
                FROM ai_recommendations
                GROUP BY asset_id
            ) latest ON r.recommendation_id = latest.latest_id
            INNER JOIN assets a ON a.asset_id = r.asset_id
                AND a.is_deleted = FALSE AND a.lifecycle_status <> 'DISPOSED'
            """ + " WHERE " + scope.sql("a") + " GROUP BY r.recommendation";
        Object[] args = scope == null ? new Object[0] : scope.args();
        return jdbcTemplate.query(sql, (rs, rn) ->
            new AiRecommendationSummaryItem(
                AiRecommendation.Recommendation.valueOf(rs.getString("recommendation")),
                rs.getLong("cnt")), args);
    }

    // What the AI is shown about an asset's history. repairFrequency counts REPAIR and CORRECTIVE
    // records only, so routine preventive upkeep (cleaning, scheduled battery swaps) isn't read as a breakdown.
    private record Inputs(BigDecimal ageYears, int conditionScore, BigDecimal totalRepairCost, int repairFrequency) {}

    // Longest record fields sent to the AI, to keep the prompt small.
    private static final int MAX_TEXT = 220;
    private static final int MAX_MAINTENANCE_ROWS = 15;

    private Inputs inputsFor(Asset asset) {
        BigDecimal ageYears = BigDecimal.valueOf(
                ChronoUnit.DAYS.between(asset.getAcquisitionDate(), AppTime.today()) / 365.25)
            .setScale(2, RoundingMode.HALF_UP);

        int conditionScore = switch (asset.getCondition()) {
            case NEW, SERVICEABLE -> 3;
            case REPAIRABLE -> 2;
            case UNSERVICEABLE -> 1;
        };

        BigDecimal totalRepairCost = jdbcTemplate.queryForObject(
            "SELECT COALESCE(SUM(cost), 0) FROM maintenance_ledger WHERE asset_id = ? AND is_deleted = 0",
            BigDecimal.class, asset.getId());
        Integer repairFrequency = jdbcTemplate.queryForObject(
            "SELECT COUNT(*) FROM maintenance_ledger WHERE asset_id = ? AND is_deleted = 0"
                + " AND maintenance_type IN ('REPAIR', 'CORRECTIVE')",
            Integer.class, asset.getId());
        return new Inputs(ageYears, conditionScore, totalRepairCost, repairFrequency);
    }

    // The asset's maintenance timeline, transfers and disposal records, as plain text lines.
    private String historyFor(Long assetId) {
        StringBuilder sb = new StringBuilder();

        List<String> maintenance = jdbcTemplate.query("""
            SELECT maintenance_date, maintenance_type, status, cost, findings, actions_taken
            FROM maintenance_ledger
            WHERE asset_id = ? AND is_deleted = 0
            ORDER BY maintenance_date DESC, maintenance_id DESC
            LIMIT ?""",
            (rs, rn) -> "- %s | %s | %s | %s | Found: %s | Done: %s".formatted(
                rs.getDate("maintenance_date"), rs.getString("maintenance_type"), rs.getString("status"),
                rs.getBigDecimal("cost") != null ? "PHP " + rs.getBigDecimal("cost") : "no cost",
                clip(rs.getString("findings")), clip(rs.getString("actions_taken"))),
            assetId, MAX_MAINTENANCE_ROWS);
        Integer totalRecords = jdbcTemplate.queryForObject(
            "SELECT COUNT(*) FROM maintenance_ledger WHERE asset_id = ? AND is_deleted = 0",
            Integer.class, assetId);
        sb.append("Maintenance records, newest first (").append(totalRecords).append(" total");
        if (totalRecords != null && totalRecords > maintenance.size()) {
            sb.append(", showing the latest ").append(maintenance.size());
        }
        sb.append("):\n");
        if (maintenance.isEmpty()) sb.append("- none logged\n");
        maintenance.forEach(line -> sb.append(line).append('\n'));

        List<String> byType = jdbcTemplate.query("""
            SELECT maintenance_type, COUNT(*) AS n, COALESCE(SUM(cost), 0) AS total
            FROM maintenance_ledger WHERE asset_id = ? AND is_deleted = 0
            GROUP BY maintenance_type ORDER BY maintenance_type""",
            (rs, rn) -> rs.getString("maintenance_type") + ": " + rs.getInt("n")
                + " (PHP " + rs.getBigDecimal("total") + ")",
            assetId);
        if (!byType.isEmpty()) sb.append("By type: ").append(String.join(", ", byType)).append('\n');

        Integer transfers = jdbcTemplate.queryForObject(
            "SELECT COUNT(*) FROM asset_history WHERE asset_id = ? AND event_type = 'TRANSFERRED'",
            Integer.class, assetId);
        sb.append("Transfers between offices: ").append(transfers).append('\n');

        List<String> disposals = jdbcTemplate.query("""
            SELECT inspection_date, disposal_status, recommended_method, reason
            FROM disposal_ledger WHERE asset_id = ? AND is_deleted = 0
            ORDER BY inspection_date DESC""",
            (rs, rn) -> "- %s | %s | %s | %s".formatted(rs.getDate("inspection_date"),
                rs.getString("disposal_status"), rs.getString("recommended_method"), clip(rs.getString("reason"))),
            assetId);
        if (!disposals.isEmpty()) {
            sb.append("Disposal records:\n");
            disposals.forEach(line -> sb.append(line).append('\n'));
        }
        return sb.toString();
    }

    private static String expectedLife(Asset asset) {
        Integer years = asset.getCategory() != null ? asset.getCategory().getUsefulLifeYears() : null;
        if (years == null) return "not set";
        LocalDate end = asset.getAcquisitionDate().plusYears(years);
        return years + " years (" + (end.isBefore(AppTime.today()) ? "ended " : "ends ") + end + ")";
    }

    private static String clip(String s) {
        if (s == null || s.isBlank()) return "-";
        String flat = s.replaceAll("\\s+", " ").trim();
        return flat.length() <= MAX_TEXT ? flat : flat.substring(0, MAX_TEXT) + "...";
    }

    // For the background worker: makes a new recommendation only when its inputs moved since the
    // latest one (condition, repair cost or repair count) or the records behind it changed
    // (recordsChanged). Age is left out: it changes every day and alone rarely changes the advice.
    // Archived and deleted assets are skipped. beforeCall runs just before Gemini is asked (the
    // worker's pacing). Returns whether a new one was made.
    public boolean refreshIfChanged(Long assetId, boolean recordsChanged, Runnable beforeCall) {
        Integer live = jdbcTemplate.queryForObject(
            "SELECT COUNT(*) FROM assets WHERE asset_id = ? AND is_deleted = 0 AND lifecycle_status <> 'ARCHIVED'",
            Integer.class, assetId);
        if (live == null || live == 0) return false;
        Optional<AiRecommendation> latest = getLatest(assetId);
        if (latest.isPresent() && !recordsChanged) {
            Inputs in = inputsFor(assetService.findById(assetId));
            AiRecommendation r = latest.get();
            boolean same = r.getConditionScore() != null && r.getConditionScore() == in.conditionScore()
                && r.getRepairFrequency() != null && r.getRepairFrequency() == in.repairFrequency()
                && r.getTotalRepairCost() != null && r.getTotalRepairCost().compareTo(in.totalRepairCost()) == 0;
            if (same) return false;
        }
        beforeCall.run();
        generate(assetId);
        return true;
    }

    public AiRecommendation generate(Long assetId) {
        geminiConfig.requireConfigured();

        Asset asset = assetService.findById(assetId);
        Inputs in = inputsFor(asset);

        AssetLifecycleAdvice advice = requestAdvice(asset, in.ageYears(), in.conditionScore(),
            in.totalRepairCost(), in.repairFrequency());

        Long newId = SpHelper.callWithOutLong(jdbcTemplate,
            "CALL sp_ai_recommendations_create(?, ?, ?, ?, ?, ?, ?, ?)",
            assetId, in.ageYears(), in.totalRepairCost(), in.repairFrequency(), in.conditionScore(),
            advice.recommendation().name(), advice.rationale());

        auditLogService.log("AI_RECOMMENDATION_GENERATED", "Assets", assetId, "asset",
            "Generated AI recommendation for " + asset.getPropertyNumber() + ": " + advice.recommendation());

        return getLatest(assetId)
            .filter(r -> r.getId().equals(newId))
            .orElseThrow(() -> new IllegalStateException("Recommendation was saved but could not be re-fetched"));
    }

    private static final String SYSTEM_PROMPT = """
        You are an asset-lifecycle advisor for the General Services Office of a Philippine \
        municipal government. You are given one asset's details and its full maintenance, transfer \
        and disposal history. Recommend exactly one action:
        - MAINTAIN: working well; keep the normal preventive schedule.
        - MONITOR: working, but there are warning signs (aging, a recent fault, worn parts); check it more often.
        - REPAIR: has a fault that is worth fixing; the repair is cheap compared with replacing it.
        - BUDGET_PRIORITY: still usable now, but it should be replaced soon, so include it in the next \
        budget (for example: old age, no longer supported, parts getting scarce, rising repair costs).
        - REVIEW_FOR_DISPOSAL: beyond economical repair now, or unserviceable, or disposal is already \
        under way; start or finish the disposal process (IIRUP).
        How to judge:
        - Read the records, not just the totals. PREVENTIVE records (cleaning, scheduled battery or lamp \
        replacement, inspections) are normal upkeep and are not signs of failure. Repeated REPAIR or \
        CORRECTIVE records for the same problem, or rising repair costs, are.
        - Compare total repair cost with the unit value, and look at the newest records and any \
        ONGOING or SCHEDULED work to see the asset's current state.
        - Age alone is not enough for REVIEW_FOR_DISPOSAL. An old asset that works and is maintained \
        is usually MONITOR or BUDGET_PRIORITY.
        - When the category has an expected useful life, compare the age with it. Nearing or past \
        that life is a reason to plan a replacement (BUDGET_PRIORITY), not on its own a reason for disposal.
        - If no maintenance is logged, that means nothing has been recorded yet, not that the asset is \
        trouble-free; do not treat it as evidence either way.
        - If a disposal record exists, say what stage it is at and what is left to do.
        Write the rationale in 3-4 plain sentences a non-technical municipal employee can act on. \
        Mention the specific facts behind the advice (for example a repeated fault, a cost compared \
        with the unit value, or an end-of-support note) and end with the next step to take. Do not \
        invent facts that are not in the data. This is advisory only; a person always makes the final \
        decision. Respond only with JSON matching the given schema.""";

    private AssetLifecycleAdvice requestAdvice(Asset asset, BigDecimal ageYears, int conditionScore,
                                                BigDecimal totalRepairCost, int repairFrequency) {
        Client client = geminiConfig.buildClient();

        String costShare = asset.getUnitValue() != null && asset.getUnitValue().signum() > 0
            ? totalRepairCost.multiply(BigDecimal.valueOf(100))
                .divide(asset.getUnitValue(), 0, RoundingMode.HALF_UP) + "% of unit value"
            : "unit value unknown";

        String prompt = """
            Asset: %s, %s
            Category: %s
            Office: %s
            Specifications: %s
            Remarks: %s
            Acquired: %s (%s years ago)
            Expected useful life for this category: %s
            Unit value: PHP %s
            Current condition: %s (score %d/3, where 3 = serviceable, 2 = repairable, 1 = unserviceable)
            Lifecycle status: %s
            Total maintenance cost: PHP %s (%s)
            Repairs (REPAIR + CORRECTIVE records): %d

            %s""".formatted(
                asset.getPropertyNumber(), asset.getDescription(),
                asset.getCategory() != null ? asset.getCategory().getCategoryName() : "Uncategorized",
                asset.getOffice() != null ? asset.getOffice().getOfficeName() : "Unassigned",
                clip(asset.getSpecifications()), clip(asset.getRemarks()),
                asset.getAcquisitionDate(), ageYears, expectedLife(asset), asset.getUnitValue(),
                asset.getCondition(), conditionScore, asset.getLifecycleStatus(),
                totalRepairCost, costShare, repairFrequency,
                historyFor(asset.getId()));

        Schema schema = Schema.builder()
            .type(Type.Known.OBJECT)
            .properties(Map.of(
                "recommendation", Schema.builder()
                    .type(Type.Known.STRING)
                    .format("enum")
                    .enum_(Arrays.stream(AiRecommendation.Recommendation.values())
                        .map(Enum::name).toArray(String[]::new))
                    .description("The recommended lifecycle action for this asset.")
                    .build(),
                "rationale", Schema.builder()
                    .type(Type.Known.STRING)
                    .description("3-4 plain-language sentences a non-technical municipal employee can act on: "
                        + "the specific facts behind the recommendation, then the next step to take.")
                    .build()))
            .required("recommendation", "rationale")
            .build();

        GenerateContentConfig config = GenerateContentConfig.builder()
            .thinkingConfig(GeminiConfig.thinking(GeminiConfig.LIGHT_THINKING))
            .systemInstruction(Content.fromParts(Part.fromText(SYSTEM_PROMPT)))
            .responseMimeType("application/json")
            .responseSchema(schema)
            .build();

        GenerateContentResponse response = geminiConfig.generate(
            client, GeminiConfig.Tier.FAST, "AI recommendation request", prompt, config);

        String json = response.text();
        if (json == null || json.isBlank()) {
            throw new IllegalStateException("The AI declined to generate a recommendation for this asset.");
        }
        try {
            return OBJECT_MAPPER.readValue(json, AssetLifecycleAdvice.class);
        } catch (Exception e) {
            log.error("Could not parse AI response for asset {}: {}", asset.getId(), json);
            throw new IllegalStateException("Could not parse the AI response: " + e.getMessage(), e);
        }
    }
}
