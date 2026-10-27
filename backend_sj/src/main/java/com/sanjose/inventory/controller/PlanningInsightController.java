package com.sanjose.inventory.controller;

import com.sanjose.inventory.service.AccessService;
import com.sanjose.inventory.service.PlanningInsightService;
import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.*;

import java.util.Map;

// Home's "Budget & Planning" section: replacement forecast + depreciation, with one AI summary.
// Admins only (budget planning is the GSO head's job; staff Home stays on their own work).
@RestController
@RequestMapping("/api/ai-insights/planning")
@RequiredArgsConstructor
public class PlanningInsightController {

    private final PlanningInsightService planningInsightService;
    private final AccessService accessService;

    @GetMapping
    public Map<String, Object> planning() {
        accessService.requireAdmin("view budget planning");
        return planningInsightService.planning();
    }

    @PostMapping("/summary")
    public Map<String, Object> summarize(@RequestParam(defaultValue = "false") boolean refresh) {
        accessService.requireAdmin("generate the budget planning summary");
        return planningInsightService.summarize(refresh);
    }
}
