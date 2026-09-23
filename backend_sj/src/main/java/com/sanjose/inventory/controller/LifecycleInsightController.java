package com.sanjose.inventory.controller;

import com.sanjose.inventory.service.AccessService;
import com.sanjose.inventory.service.LifecycleInsightService;
import com.sanjose.inventory.service.LifecycleInsightService.Range;
import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.*;

import java.util.Map;

// Maintenance / disposal activity over a period, with an optional AI-written summary.
// Staff only see their own office (AccessService.scopeOfficeId).
@RestController
@RequestMapping("/api/ai-insights/lifecycle")
@RequiredArgsConstructor
public class LifecycleInsightController {

    private final LifecycleInsightService lifecycleInsightService;
    private final AccessService accessService;

    @GetMapping
    public Map<String, Object> stats(@RequestParam(defaultValue = "month") String range) {
        return lifecycleInsightService.stats(Range.parse(range), accessService.scopeOfficeId());
    }

    @PostMapping("/summary")
    public Map<String, Object> summarize(@RequestParam(defaultValue = "month") String range) {
        return lifecycleInsightService.summarize(Range.parse(range), accessService.scopeOfficeId());
    }
}
