package com.sanjose.inventory.controller;

import com.sanjose.inventory.service.AccessService;
import com.sanjose.inventory.entity.DisposalJustification;
import com.sanjose.inventory.exception.ResourceNotFoundException;
import com.sanjose.inventory.service.DisposalJustificationService;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/disposal/{disposalId}/justification")
@RequiredArgsConstructor
public class DisposalJustificationController {

    private final DisposalJustificationService disposalJustificationService;
    private final AccessService accessService;

    @GetMapping
    public DisposalJustification getLatest(@PathVariable Long disposalId) {
        accessService.requireDisposalAccess(disposalId);
        return disposalJustificationService.getLatest(disposalId)
            .orElseThrow(() -> new ResourceNotFoundException(
                "No AI justification generated yet for disposal record: " + disposalId));
    }

    @PostMapping
    public ResponseEntity<DisposalJustification> generate(@PathVariable Long disposalId) {
        accessService.requireDisposalAccess(disposalId);
        return ResponseEntity.ok(disposalJustificationService.generate(disposalId));
    }
}
