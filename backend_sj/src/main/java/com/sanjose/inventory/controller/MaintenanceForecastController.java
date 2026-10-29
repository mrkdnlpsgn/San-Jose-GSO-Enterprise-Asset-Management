package com.sanjose.inventory.controller;

import com.sanjose.inventory.service.AccessService;
import com.sanjose.inventory.service.MaintenanceForecastService;
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

    @GetMapping
    public Map<String, Object> forecast(@RequestParam(defaultValue = "" + MaintenanceForecastService.DEFAULT_PRICE_INCREASE) double priceIncrease) {
        return maintenanceForecastService.forecast(priceIncrease, accessService.staffScope());
    }
}
