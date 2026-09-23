package com.sanjose.inventory.service;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.google.genai.Client;
import com.google.genai.errors.ApiException;
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
import java.time.temporal.ChronoUnit;
import java.util.Arrays;
import java.util.List;
import java.util.Map;
import java.util.Optional;

@Slf4j
@Service
@Transactional
public class AiRecommendationService {

    private static final String MODEL = "gemini-2.5-flash";
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

    // officeId null = every office (admin)
    public List<AiRecommendationSummaryItem> getSummary(Long officeId) {
        String sql = officeId == null ? "CALL sp_ai_recommendations_summary()" : "CALL sp_ai_recommendations_summary_by_office(?)";
        Object[] args = officeId == null ? new Object[0] : new Object[]{ officeId };
        return jdbcTemplate.query(sql, (rs, rn) ->
            new AiRecommendationSummaryItem(
                AiRecommendation.Recommendation.valueOf(rs.getString("recommendation")),
                rs.getLong("cnt")), args);
    }

    public AiRecommendation generate(Long assetId) {
        geminiConfig.requireConfigured();

        Asset asset = assetService.findById(assetId);

        BigDecimal ageYears = BigDecimal.valueOf(
                ChronoUnit.DAYS.between(asset.getAcquisitionDate(), LocalDate.now()) / 365.25)
            .setScale(2, RoundingMode.HALF_UP);

        int conditionScore = switch (asset.getCondition()) {
            case SERVICEABLE -> 3;
            case REPAIRABLE -> 2;
            case UNSERVICEABLE -> 1;
        };

        BigDecimal totalRepairCost = jdbcTemplate.queryForObject(
            "SELECT COALESCE(SUM(cost), 0) FROM maintenance_ledger WHERE asset_id = ? AND is_deleted = 0",
            BigDecimal.class, assetId);
        Integer repairFrequency = jdbcTemplate.queryForObject(
            "SELECT COUNT(*) FROM maintenance_ledger WHERE asset_id = ? AND is_deleted = 0",
            Integer.class, assetId);

        AssetLifecycleAdvice advice = requestAdvice(asset, ageYears, conditionScore, totalRepairCost, repairFrequency);

        Long newId = SpHelper.callWithOutLong(jdbcTemplate,
            "CALL sp_ai_recommendations_create(?, ?, ?, ?, ?, ?, ?, ?)",
            assetId, ageYears, totalRepairCost, repairFrequency, conditionScore,
            advice.recommendation().name(), advice.rationale());

        auditLogService.log("AI_RECOMMENDATION_GENERATED", "Assets", assetId, "asset",
            "Generated AI recommendation for " + asset.getPropertyNumber() + ": " + advice.recommendation());

        return getLatest(assetId)
            .filter(r -> r.getId().equals(newId))
            .orElseThrow(() -> new IllegalStateException("Recommendation was saved but could not be re-fetched"));
    }

    private static final String SYSTEM_PROMPT = """
        You are an asset-lifecycle advisor for a Philippine municipal government's ICT/equipment \
        inventory system. Given an asset's age, condition, value, and recorded repair history, \
        recommend exactly one lifecycle action and explain it in 2-3 sentences a non-technical \
        municipal employee can act on. Be conservative: a repair-frequency or cost of zero means no \
        maintenance has been logged yet, not that the asset is trouble-free — do not treat it as \
        evidence either way. Only recommend REVIEW_FOR_DISPOSAL or BUDGET_PRIORITY when the age, \
        condition, or repair history clearly support it. This recommendation is advisory only — a \
        human always makes the final disposal decision. Respond only with JSON matching the given schema.""";

    private AssetLifecycleAdvice requestAdvice(Asset asset, BigDecimal ageYears, int conditionScore,
                                                BigDecimal totalRepairCost, int repairFrequency) {
        Client client = geminiConfig.buildClient();

        String prompt = """
            Asset: %s — %s
            Category: %s
            Office: %s
            Age: %s years
            Unit value: PHP %s
            Quantity: %d
            Current condition: %s (score %d/3, where 3 = serviceable, 2 = repairable, 1 = unserviceable)
            Lifecycle status: %s
            Total recorded repair cost: PHP %s
            Repair frequency (recorded maintenance events): %d
            """.formatted(
                asset.getPropertyNumber(), asset.getDescription(),
                asset.getCategory() != null ? asset.getCategory().getCategoryName() : "Uncategorized",
                asset.getOffice() != null ? asset.getOffice().getOfficeName() : "Unassigned",
                ageYears, asset.getUnitValue(), asset.getQuantity(),
                asset.getCondition(), conditionScore, asset.getLifecycleStatus(),
                totalRepairCost, repairFrequency);

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
                    .description("2-3 plain-language sentences a non-technical municipal employee can act on, "
                        + "explaining why this recommendation was made.")
                    .build()))
            .required("recommendation", "rationale")
            .build();

        GenerateContentConfig config = GenerateContentConfig.builder()
            .systemInstruction(Content.fromParts(Part.fromText(SYSTEM_PROMPT)))
            .responseMimeType("application/json")
            .responseSchema(schema)
            .build();

        GenerateContentResponse response;
        try {
            response = client.models.generateContent(MODEL, prompt, config);
        } catch (ApiException e) {
            log.error("AI recommendation request failed for asset {}: {}", asset.getId(), e.getMessage());
            throw new IllegalStateException("AI recommendation request failed: " + e.getMessage(), e);
        }

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
