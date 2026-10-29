package com.sanjose.inventory.controller;

import com.sanjose.inventory.service.AccessService;
import com.sanjose.inventory.service.RepairRiskService;
import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.*;

import java.util.Map;

// Assets likely to need repair or maintenance in the next 12 months, from the machine-learning
// model in RepairRiskService (Reports; Home shows the totals through /api/ai-insights/planning).
// Staff only see their own assets (AccessService.staffScope).
@RestController
@RequestMapping("/api/ai-insights/repair-risk")
@RequiredArgsConstructor
public class RepairRiskController {

    private final RepairRiskService repairRiskService;
    private final AccessService accessService;

    @GetMapping
    public Map<String, Object> forecast(@RequestParam(defaultValue = "false") boolean items) {
        return repairRiskService.forecast(items, accessService.staffScope());
    }
}
