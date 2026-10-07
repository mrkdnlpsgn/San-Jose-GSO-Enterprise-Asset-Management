package com.sanjose.inventory.controller;

import com.sanjose.inventory.service.AccessService;
import com.sanjose.inventory.entity.DisposalJustification;
import com.sanjose.inventory.service.AiAutoGenerator;
import com.sanjose.inventory.service.DisposalJustificationService;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;


@RestController
@RequestMapping("/api/disposal/{disposalId}/justification")
@RequiredArgsConstructor
public class DisposalJustificationController {

    private final DisposalJustificationService disposalJustificationService;
    private final AccessService accessService;
    private final AiAutoGenerator aiAutoGenerator;

    // None yet: a 404 that also says whether AI is paused (daily quota used up) — see
    // AiAutoGenerator.notReady. Nothing is generated just by viewing (Gemini free-plan quota).
    @GetMapping
    public ResponseEntity<?> getLatest(@PathVariable Long disposalId) {
        accessService.requireDisposalAccess(disposalId);
        return disposalJustificationService.getLatest(disposalId)
            .<ResponseEntity<?>>map(ResponseEntity::ok)
            .orElseGet(() -> ResponseEntity.status(HttpStatus.NOT_FOUND).body(aiAutoGenerator.notReady("No AI justification generated yet for disposal record: " + disposalId)));
    }

    @PostMapping
    public ResponseEntity<DisposalJustification> generate(@PathVariable Long disposalId) {
        accessService.requireDisposalAccess(disposalId);
        return ResponseEntity.ok(disposalJustificationService.generate(disposalId));
    }
}
