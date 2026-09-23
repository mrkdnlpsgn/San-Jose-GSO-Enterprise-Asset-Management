package com.sanjose.inventory.controller;

import com.sanjose.inventory.service.AccessService;
import com.sanjose.inventory.dto.AiRecommendationSummaryItem;
import com.sanjose.inventory.service.AiRecommendationService;
import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

@RestController
@RequestMapping("/api/ai-recommendations")
@RequiredArgsConstructor
public class AiRecommendationSummaryController {

    private final AiRecommendationService aiRecommendationService;
    private final AccessService accessService;

    @GetMapping("/summary")
    public List<AiRecommendationSummaryItem> getSummary() {
        return aiRecommendationService.getSummary(accessService.scopeOfficeId());
    }
}
