package com.sanjose.inventory.service;

import com.sanjose.inventory.config.AppTime;
import com.google.genai.Client;
import com.google.genai.errors.ApiException;
import com.google.genai.types.Content;
import com.google.genai.types.GenerateContentConfig;
import com.google.genai.types.GenerateContentResponse;
import com.google.genai.types.Part;
import com.sanjose.inventory.config.GeminiConfig;
import com.sanjose.inventory.config.SpHelper;
import com.sanjose.inventory.entity.Asset;
import com.sanjose.inventory.entity.DisposalJustification;
import com.sanjose.inventory.entity.DisposalLedger;
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
import java.util.List;
import java.util.Optional;

@Slf4j
@Service
@Transactional
public class DisposalJustificationService {

    private static final String MODEL = "gemini-2.5-flash";

    private final JdbcTemplate jdbcTemplate;
    private final DisposalLedgerService disposalLedgerService;
    private final AssetService assetService;
    private final GeminiConfig geminiConfig;

    public DisposalJustificationService(JdbcTemplate jdbcTemplate, DisposalLedgerService disposalLedgerService,
                                         AssetService assetService, GeminiConfig geminiConfig) {
        this.jdbcTemplate = jdbcTemplate;
        this.disposalLedgerService = disposalLedgerService;
        this.assetService = assetService;
        this.geminiConfig = geminiConfig;
    }

    private static final RowMapper<DisposalJustification> MAPPER = (rs, rn) -> {
        DisposalJustification j = new DisposalJustification();
        j.setId(rs.getLong("id"));
        j.setDisposalId(rs.getLong("disposal_id"));
        j.setJustification(rs.getString("justification"));
        Timestamp genAt = rs.getTimestamp("generated_at");
        j.setGeneratedAt(genAt != null ? genAt.toLocalDateTime() : null);
        j.setGeneratedBySystem(rs.getBoolean("generated_by_system"));
        return j;
    };

    public Optional<DisposalJustification> getLatest(Long disposalId) {
        List<DisposalJustification> list = jdbcTemplate.query(
            "CALL sp_disposal_justifications_get_latest(?)", MAPPER, disposalId);
        return list.isEmpty() ? Optional.empty() : Optional.of(list.get(0));
    }

    public DisposalJustification generate(Long disposalId) {
        geminiConfig.requireConfigured();

        DisposalLedger disposal = disposalLedgerService.findById(disposalId);
        Asset asset = assetService.findById(disposal.getAsset().getId());

        String text = requestJustification(disposal, asset);

        Long newId = SpHelper.callWithOutLong(jdbcTemplate,
            "CALL sp_disposal_justifications_create(?, ?, ?)", disposalId, text);

        return getLatest(disposalId)
            .filter(j -> j.getId().equals(newId))
            .orElseThrow(() -> new IllegalStateException("Justification was saved but could not be re-fetched"));
    }

    private static final String SYSTEM_PROMPT = """
        You draft disposal justification write-ups for a Philippine municipal government's ICT/equipment \
        inventory system, for internal use in preparing a formal property disposal request. Write 2-4 \
        short paragraphs covering: (1) identification of the asset and why it is being considered for \
        disposal, (2) the inspection findings and condition supporting that conclusion, including a brief \
        cost/economic justification if repair cost or age data is meaningful, (3) the recommended disposal \
        method and why it fits. Use a formal, factual tone appropriate for an official government record. \
        Do NOT invent or cite specific COA circular numbers, memorandum numbers, statute sections, or other \
        legal citations you cannot verify — refer generically to "applicable government property disposal \
        regulations" instead. Do NOT fabricate figures not given to you. This draft is a starting point for \
        the responsible officer to review and finalize — do not claim final authority or pre-approve anything. \
        Output plain text only, no markdown formatting, no headers.""";

    private String requestJustification(DisposalLedger disposal, Asset asset) {
        Client client = geminiConfig.buildClient();

        String ageYears = asset.getAcquisitionDate() != null
            ? BigDecimal.valueOf(ChronoUnit.DAYS.between(asset.getAcquisitionDate(), AppTime.today()) / 365.25)
                .setScale(1, RoundingMode.HALF_UP).toString()
            : "unknown";

        BigDecimal totalRepairCost = jdbcTemplate.queryForObject(
            "SELECT COALESCE(SUM(cost), 0) FROM maintenance_ledger WHERE asset_id = ? AND is_deleted = 0",
            BigDecimal.class, asset.getId());
        Integer repairFrequency = jdbcTemplate.queryForObject(
            "SELECT COUNT(*) FROM maintenance_ledger WHERE asset_id = ? AND is_deleted = 0",
            Integer.class, asset.getId());

        String prompt = """
            Asset: %s — %s
            Category: %s
            Office: %s
            Age: %s years
            Unit value: PHP %s
            Quantity: %d
            Current condition: %s
            Recorded repair cost to date: PHP %s
            Recorded repair frequency: %d

            Disposal record on file:
            Reason given: %s
            Inspection findings: %s
            Inspection date: %s
            Recommended method: %s
            Status: %s
            """.formatted(
                asset.getPropertyNumber(), asset.getDescription(),
                asset.getCategory() != null ? asset.getCategory().getCategoryName() : "Uncategorized",
                asset.getOffice() != null ? asset.getOffice().getOfficeName() : "Unassigned",
                ageYears, asset.getUnitValue(), asset.getQuantity(), asset.getCondition(),
                totalRepairCost, repairFrequency,
                disposal.getReason(), disposal.getInspectionFindings(), disposal.getInspectionDate(),
                disposal.getRecommendedMethod(), disposal.getDisposalStatus());

        GenerateContentConfig config = GenerateContentConfig.builder()
            .systemInstruction(Content.fromParts(Part.fromText(SYSTEM_PROMPT)))
            .build();

        GenerateContentResponse response;
        try {
            response = client.models.generateContent(MODEL, prompt, config);
        } catch (ApiException e) {
            log.error("AI justification request failed for disposal {}: {}", disposal.getId(), e.getMessage());
            throw geminiConfig.failure("AI justification request", e);
        }

        String text = response.text();
        if (text == null || text.isBlank()) {
            throw new IllegalStateException("The AI did not return a justification for this disposal record.");
        }
        return text.trim();
    }
}
