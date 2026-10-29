package com.sanjose.inventory.controller;

import com.sanjose.inventory.service.AccessService;
import com.sanjose.inventory.service.PlanningInsightService;
import com.sanjose.inventory.service.PlanningSettingsService;
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
    private final PlanningSettingsService planningSettings;

    @GetMapping
    public Map<String, Object> planning() {
        accessService.requireAllAssets("view budget planning");
        return planningInsightService.planning();
    }

    public record PriceIncreaseRequest(Double percent) {}

    // The yearly price increase every forecast uses; administrators only. Answers with the
    // planning figures worked out again at the new rate.
    @PutMapping("/price-increase")
    public Map<String, Object> setPriceIncrease(@RequestBody PriceIncreaseRequest req) {
        accessService.requireAdmin("change the yearly price increase");
        planningSettings.setPriceIncreasePercent(req == null ? null : req.percent(), accessService.current().id());
        return planningInsightService.planning();
    }

    @PostMapping("/summary")
    public Map<String, Object> summarize(@RequestParam(defaultValue = "false") boolean refresh) {
        accessService.requireAllAssets("generate the budget planning summary");
        return planningInsightService.summarize(refresh);
    }
}
