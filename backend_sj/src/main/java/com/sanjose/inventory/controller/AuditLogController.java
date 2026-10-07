package com.sanjose.inventory.controller;

import com.sanjose.inventory.entity.AuditLog;
import com.sanjose.inventory.entity.AuditLogDigest;
import com.sanjose.inventory.service.AiAutoGenerator;
import com.sanjose.inventory.service.AuditLogDigestService;
import com.sanjose.inventory.service.AuditLogService;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@RestController
@RequestMapping("/api/audit-logs")
@RequiredArgsConstructor
public class AuditLogController {

    private final AuditLogService auditLogService;
    private final AuditLogDigestService auditLogDigestService;
    private final AiAutoGenerator aiAutoGenerator;

    @GetMapping
    public List<AuditLog> getAll(@RequestParam(required = false) String search) {
        return auditLogService.findAll(search);
    }

    // None yet: a 404 that also says whether AI is paused (daily quota used up) — see
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
}
