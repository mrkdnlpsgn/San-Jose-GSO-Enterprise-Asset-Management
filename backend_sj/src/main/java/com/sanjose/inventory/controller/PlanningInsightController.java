package com.sanjose.inventory.controller;

import com.sanjose.inventory.service.AccessService;
import com.sanjose.inventory.service.PlanningInsightService;
import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.*;

import java.util.Map;

// Home's "Budget & Planning" section: replacement forecast + depreciation, with one AI summary.
// Admins and Admin-Staff (both see the entire inventory); staff Home stays on their own work.
@RestController
@RequestMapping("/api/ai-insights/planning")
@RequiredArgsConstructor
public class PlanningInsightController {

    private final PlanningInsightService planningInsightService;
    private final AccessService accessService;

    @GetMapping
    public Map<String, Object> planning() {
        accessService.requireAllAssets("view budget planning");
        return planningInsightService.planning();
    }

    @PostMapping("/summary")
    public Map<String, Object> summarize(@RequestParam(defaultValue = "false") boolean refresh) {
        accessService.requireAllAssets("generate the budget planning summary");
        return planningInsightService.summarize(refresh);
    }
}
