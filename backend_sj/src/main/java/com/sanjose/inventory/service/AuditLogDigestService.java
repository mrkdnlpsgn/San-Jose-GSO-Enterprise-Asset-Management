package com.sanjose.inventory.service;

import com.google.genai.Client;
import com.google.genai.errors.ApiException;
import com.google.genai.types.Content;
import com.google.genai.types.GenerateContentConfig;
import com.google.genai.types.GenerateContentResponse;
import com.google.genai.types.Part;
import com.sanjose.inventory.config.GeminiConfig;
import com.sanjose.inventory.config.SpHelper;
import com.sanjose.inventory.entity.AuditLog;
import com.sanjose.inventory.entity.AuditLogDigest;
import lombok.extern.slf4j.Slf4j;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.sanjose.inventory.config.AppTime;
import java.sql.Timestamp;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.util.List;
import java.util.Optional;
import java.util.stream.Collectors;

@Slf4j
@Service
@Transactional
public class AuditLogDigestService {

    private static final String MODEL = "gemini-2.5-flash";
    private static final int MAX_ENTRIES = 50;

    private final JdbcTemplate jdbcTemplate;
    private final AuditLogService auditLogService;
    private final GeminiConfig geminiConfig;

    public AuditLogDigestService(JdbcTemplate jdbcTemplate, AuditLogService auditLogService,
                                  GeminiConfig geminiConfig) {
        this.jdbcTemplate = jdbcTemplate;
        this.auditLogService = auditLogService;
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

        List<AuditLog> logs = auditLogService.findAll(null);
        if (logs.isEmpty()) {
            throw new IllegalStateException("No audit log activity to summarize yet.");
        }
        List<AuditLog> recent = logs.size() > MAX_ENTRIES ? logs.subList(0, MAX_ENTRIES) : logs;

        String text = requestDigest(recent);

        Long newId = SpHelper.callWithOutLong(jdbcTemplate,
            "CALL sp_audit_log_digests_create(?, ?, ?)", text, recent.size());

        return getLatest()
            .filter(d -> d.getId().equals(newId))
            .orElseThrow(() -> new IllegalStateException("Digest was saved but could not be re-fetched"));
    }

    private static final String SYSTEM_PROMPT = """
        You write a short plain-English activity digest for the ICT administrator of a Philippine municipal \
        government asset inventory system, based on a list of recent audit log entries. Summarize in 2-4 \
        short sentences: what kinds of actions happened and roughly how many, which modules were most \
        active, and call out anything that looks unusual or worth a second look (e.g. a burst of deletions, \
        repeated actions by the same user in a short span, or activity timestamps outside normal business \
        hours). If nothing stands out, say so plainly instead of inventing a concern. Do not list every \
        entry individually — synthesize. Plain text only, no markdown, no headers.""";

    // Stored times are UTC; the "outside business hours" check needs Philippine time.
    private static String manilaTime(LocalDateTime utc) {
        if (utc == null) return "unknown time";
        return utc.atOffset(ZoneOffset.UTC).atZoneSameInstant(AppTime.ZONE).toLocalDateTime().toString();
    }

    private String requestDigest(List<AuditLog> logs) {
        Client client = geminiConfig.buildClient();

        String logLines = logs.stream()
            .map(l -> "- [%s] %s | module=%s | by=%s | target=%s#%s | %s".formatted(
                manilaTime(l.getLoggedAt()), l.getAction(), l.getModule(),
                l.getUser() != null ? l.getUser().getUsername() : "unknown",
                l.getTargetType(), l.getTargetId(),
                l.getDetails() != null ? l.getDetails() : ""))
            .collect(Collectors.joining("\n"));

        String prompt = "Recent audit log entries (most recent first; times are Philippine time):\n" + logLines;

        GenerateContentConfig config = GenerateContentConfig.builder()
            .systemInstruction(Content.fromParts(Part.fromText(SYSTEM_PROMPT)))
            .build();

        GenerateContentResponse response;
        try {
            response = client.models.generateContent(MODEL, prompt, config);
        } catch (ApiException e) {
            log.error("Audit log digest request failed: {}", e.getMessage());
            throw geminiConfig.failure("AI digest request", e);
        }

        String text = response.text();
        if (text == null || text.isBlank()) {
            throw new IllegalStateException("The AI did not return a digest.");
        }
        return text.trim();
    }
}
