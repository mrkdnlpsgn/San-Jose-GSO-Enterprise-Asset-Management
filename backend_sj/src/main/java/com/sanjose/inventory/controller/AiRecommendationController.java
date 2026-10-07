package com.sanjose.inventory.controller;

import com.sanjose.inventory.service.AccessService;
import com.sanjose.inventory.entity.AiRecommendation;
import com.sanjose.inventory.service.AiAutoGenerator;
import com.sanjose.inventory.service.AiRecommendationService;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;


@RestController
@RequestMapping("/api/assets/{assetId}/recommendation")
@RequiredArgsConstructor
public class AiRecommendationController {

    private final AiRecommendationService aiRecommendationService;
    private final AccessService accessService;
    private final AiAutoGenerator aiAutoGenerator;

    // None yet: a 404 that also says whether AI is paused (daily quota used up) — see
    // AiAutoGenerator.notReady. Nothing is generated just by viewing (Gemini free-plan quota).
    @GetMapping
    public ResponseEntity<?> getLatest(@PathVariable Long assetId) {
        accessService.requireAssetAccess(assetId);
        return aiRecommendationService.getLatest(assetId)
            .<ResponseEntity<?>>map(ResponseEntity::ok)
            .orElseGet(() -> ResponseEntity.status(HttpStatus.NOT_FOUND).body(aiAutoGenerator.notReady("No recommendation generated yet for asset: " + assetId)));
    }

    @PostMapping
    public ResponseEntity<AiRecommendation> generate(@PathVariable Long assetId) {
        accessService.requireAssetAccess(assetId);
        return ResponseEntity.ok(aiRecommendationService.generate(assetId));
    }
}
