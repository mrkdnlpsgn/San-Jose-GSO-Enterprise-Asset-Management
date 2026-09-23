package com.sanjose.inventory.controller;

import com.sanjose.inventory.service.AccessService;
import com.sanjose.inventory.entity.AiRecommendation;
import com.sanjose.inventory.exception.ResourceNotFoundException;
import com.sanjose.inventory.service.AiRecommendationService;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/assets/{assetId}/recommendation")
@RequiredArgsConstructor
public class AiRecommendationController {

    private final AiRecommendationService aiRecommendationService;
    private final AccessService accessService;

    @GetMapping
    public AiRecommendation getLatest(@PathVariable Long assetId) {
        accessService.requireAssetAccess(assetId);
        return aiRecommendationService.getLatest(assetId)
            .orElseThrow(() -> new ResourceNotFoundException("No recommendation generated yet for asset: " + assetId));
    }

    @PostMapping
    public ResponseEntity<AiRecommendation> generate(@PathVariable Long assetId) {
        accessService.requireAssetAccess(assetId);
        return ResponseEntity.ok(aiRecommendationService.generate(assetId));
    }
}
