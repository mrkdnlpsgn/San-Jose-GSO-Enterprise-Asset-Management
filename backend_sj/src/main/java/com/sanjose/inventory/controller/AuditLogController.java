package com.sanjose.inventory.controller;

import com.sanjose.inventory.entity.AuditLog;
import com.sanjose.inventory.entity.AuditLogDigest;
import com.sanjose.inventory.service.AiAutoGenerator;
import com.sanjose.inventory.service.AuditLogArchiveService;
import com.sanjose.inventory.service.AuditLogDigestService;
import com.sanjose.inventory.service.AuditLogService;
import lombok.RequiredArgsConstructor;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.io.IOException;
import java.io.OutputStreamWriter;
import java.io.Writer;
import java.nio.charset.StandardCharsets;
import java.time.LocalDate;
import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/audit-logs")
@RequiredArgsConstructor
public class AuditLogController {

    private final AuditLogService auditLogService;
    private final AuditLogDigestService auditLogDigestService;
    private final AiAutoGenerator aiAutoGenerator;
    private final AuditLogArchiveService archiveService;

    @GetMapping
    public List<AuditLog> getAll(@RequestParam(required = false) String search) {
        return auditLogService.findAll(search);
    }

    // None yet: a 404 that also says whether AI is paused (daily quota used up) - see
    // AiAutoGenerator.notReady. Nothing is generated just by viewing (Gemini free-plan quota).
    @GetMapping("/digest")
    public ResponseEntity<?> getLatestDigest() {
        return auditLogDigestService.getLatest()
            .<ResponseEntity<?>>map(ResponseEntity::ok)
            .orElseGet(() -> ResponseEntity.status(HttpStatus.NOT_FOUND).body(aiAutoGenerator.notReady("No AI digest generated yet.")));
    }

    @PostMapping("/digest")
    public ResponseEntity<AuditLogDigest> generateDigest() {
        return ResponseEntity.ok(auditLogDigestService.generate());
    }

    // ── archive: entries older than the retention period (see AuditLogArchiveService) ──

    @GetMapping("/archive/summary")
    public Map<String, Object> archiveSummary() {
        return archiveService.summary();
    }

    // Moves old entries now instead of waiting for the nightly run.
    @PostMapping("/archive/run")
    public Map<String, Object> archiveNow() {
        int moved = archiveService.archiveOldEntries();
        Map<String, Object> summary = new java.util.LinkedHashMap<>(archiveService.summary());
        summary.put("moved", moved);
        return summary;
    }

    // CSV of archived entries; from/to are Philippine dates (yyyy-MM-dd), both optional.
    @GetMapping("/archive/export")
    public void exportArchive(
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate from,
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate to,
            HttpServletResponse response) throws IOException {
        String name = "audit-logs-archive"
            + (from != null ? "-from-" + from : "") + (to != null ? "-to-" + to : "") + ".csv";
        response.setContentType("text/csv; charset=UTF-8");
        response.setHeader("Content-Disposition", "attachment; filename=\"" + name + "\"");
        Writer out = new OutputStreamWriter(response.getOutputStream(), StandardCharsets.UTF_8);
        archiveService.exportCsv(from, to, out);
    }
}
