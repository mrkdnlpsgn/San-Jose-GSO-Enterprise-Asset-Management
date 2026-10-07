package com.sanjose.inventory.service;

import com.google.genai.Client;
import com.google.genai.errors.ApiException;
import com.google.genai.types.Content;
import com.google.genai.types.GenerateContentConfig;
import com.google.genai.types.GenerateContentResponse;
import com.google.genai.types.Part;
import com.sanjose.inventory.config.GeminiConfig;
import com.sanjose.inventory.config.SpHelper;
import com.sanjose.inventory.entity.MaintenanceLedger;
import com.sanjose.inventory.entity.MaintenanceSummary;
import lombok.extern.slf4j.Slf4j;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.sql.Timestamp;
import java.util.List;
import java.util.Optional;

@Slf4j
@Service
@Transactional
public class MaintenanceSummaryService {

    private static final String MODEL = "gemini-2.5-flash";

    private final JdbcTemplate jdbcTemplate;
    private final MaintenanceLedgerService maintenanceLedgerService;
    private final GeminiConfig geminiConfig;

    public MaintenanceSummaryService(JdbcTemplate jdbcTemplate, MaintenanceLedgerService maintenanceLedgerService,
                                      GeminiConfig geminiConfig) {
        this.jdbcTemplate = jdbcTemplate;
        this.maintenanceLedgerService = maintenanceLedgerService;
        this.geminiConfig = geminiConfig;
    }

    private static final RowMapper<MaintenanceSummary> MAPPER = (rs, rn) -> {
        MaintenanceSummary s = new MaintenanceSummary();
        s.setId(rs.getLong("id"));
        s.setMaintenanceId(rs.getLong("maintenance_id"));
        s.setSummary(rs.getString("summary"));
        Timestamp genAt = rs.getTimestamp("generated_at");
        s.setGeneratedAt(genAt != null ? genAt.toLocalDateTime() : null);
        s.setGeneratedBySystem(rs.getBoolean("generated_by_system"));
        return s;
    };

    public Optional<MaintenanceSummary> getLatest(Long maintenanceId) {
        List<MaintenanceSummary> list = jdbcTemplate.query(
            "CALL sp_maintenance_summaries_get_latest(?)", MAPPER, maintenanceId);
        return list.isEmpty() ? Optional.empty() : Optional.of(list.get(0));
    }

    public MaintenanceSummary generate(Long maintenanceId) {
        geminiConfig.requireConfigured();

        MaintenanceLedger record = maintenanceLedgerService.findById(maintenanceId);
        String text = requestSummary(record);

        Long newId = SpHelper.callWithOutLong(jdbcTemplate,
            "CALL sp_maintenance_summaries_create(?, ?, ?)", maintenanceId, text);

        return getLatest(maintenanceId)
            .filter(s -> s.getId().equals(newId))
            .orElseThrow(() -> new IllegalStateException("Summary was saved but could not be re-fetched"));
    }

    private static final String SYSTEM_PROMPT = """
        You write a one-sentence summary of a maintenance record for a municipal government ICT/equipment \
        inventory system, to be shown in a compact list view. Read the maintenance type, findings, and \
        actions taken, and produce ONE short sentence (under 20 words) that captures what was wrong and \
        what was done about it. Plain language, no markdown, no leading label like "Summary:". If either \
        findings or actions is empty or unclear, say so briefly rather than guessing.""";

    private String requestSummary(MaintenanceLedger record) {
        Client client = geminiConfig.buildClient();

        String prompt = """
            Maintenance type: %s
            Status: %s
            Findings: %s
            Actions taken: %s
            """.formatted(record.getMaintenanceType(), record.getStatus(),
                record.getFindings(), record.getActionsTaken());

        GenerateContentConfig config = GenerateContentConfig.builder()
            .systemInstruction(Content.fromParts(Part.fromText(SYSTEM_PROMPT)))
            .build();

        GenerateContentResponse response;
        try {
            response = client.models.generateContent(MODEL, prompt, config);
        } catch (ApiException e) {
            log.error("Maintenance summary request failed for record {}: {}", record.getId(), e.getMessage());
            throw geminiConfig.failure("AI summary request", e);
        }

        String text = response.text();
        if (text == null || text.isBlank()) {
            throw new IllegalStateException("The AI did not return a summary for this maintenance record.");
        }
        return text.trim();
    }
}
