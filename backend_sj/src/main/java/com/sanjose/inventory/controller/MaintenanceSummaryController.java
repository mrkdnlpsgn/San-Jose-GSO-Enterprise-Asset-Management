package com.sanjose.inventory.controller;

import com.sanjose.inventory.service.AccessService;
import com.sanjose.inventory.entity.MaintenanceSummary;
import com.sanjose.inventory.service.AiAutoGenerator;
import com.sanjose.inventory.service.MaintenanceSummaryService;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;


@RestController
@RequestMapping("/api/maintenance/{maintenanceId}/summary")
@RequiredArgsConstructor
public class MaintenanceSummaryController {

    private final MaintenanceSummaryService maintenanceSummaryService;
    private final AccessService accessService;
    private final AiAutoGenerator aiAutoGenerator;

    // None yet: a 404 that also says whether AI is paused (daily quota used up) — see
    // AiAutoGenerator.notReady. Nothing is generated just by viewing (Gemini free-plan quota).
    @GetMapping
    public ResponseEntity<?> getLatest(@PathVariable Long maintenanceId) {
        accessService.requireMaintenanceAccess(maintenanceId);
        return maintenanceSummaryService.getLatest(maintenanceId)
            .<ResponseEntity<?>>map(ResponseEntity::ok)
            .orElseGet(() -> ResponseEntity.status(HttpStatus.NOT_FOUND).body(aiAutoGenerator.notReady("No AI summary generated yet for maintenance record: " + maintenanceId)));
    }

    @PostMapping
    public ResponseEntity<MaintenanceSummary> generate(@PathVariable Long maintenanceId) {
        accessService.requireMaintenanceAccess(maintenanceId);
        return ResponseEntity.ok(maintenanceSummaryService.generate(maintenanceId));
    }
}
