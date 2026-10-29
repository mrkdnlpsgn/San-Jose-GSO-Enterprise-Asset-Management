package com.sanjose.inventory.controller;

import com.sanjose.inventory.service.AccessService;
import com.sanjose.inventory.service.MaintenanceForecastService;
import com.sanjose.inventory.service.PlanningSettingsService;
import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.*;

import java.util.Map;

// Repair and maintenance spending per year and the estimate for next year (Reports; the Home
// section uses /api/ai-insights/planning). Staff only see their own assets (AccessService.staffScope).
@RestController
@RequestMapping("/api/ai-insights/maintenance-forecast")
@RequiredArgsConstructor
public class MaintenanceForecastController {

    private final MaintenanceForecastService maintenanceForecastService;
    private final AccessService accessService;
    private final PlanningSettingsService planningSettings;

    // The yearly price increase is the one an admin set (PlanningSettingsService), never the
    // caller's, so Home, Reports and older app versions (which still send priceIncrease) agree.
    @GetMapping
    public Map<String, Object> forecast() {
        return maintenanceForecastService.forecast(planningSettings.priceIncreasePercent(), accessService.staffScope());
    }
}
