package com.sanjose.inventory.controller;

import com.sanjose.inventory.service.AccessService;
import com.sanjose.inventory.service.PlanningSettingsService;
import com.sanjose.inventory.service.ReplacementForecastService;
import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.*;

import java.util.Map;

// Assets due for replacement over the next few years and their estimated cost (Reports; the Home
// section uses /api/ai-insights/planning). Staff only see their own assets (AccessService.staffScope).
@RestController
@RequestMapping("/api/ai-insights/replacement-forecast")
@RequiredArgsConstructor
public class ReplacementForecastController {

    private final ReplacementForecastService replacementForecastService;
    private final AccessService accessService;
    private final PlanningSettingsService planningSettings;

    // The yearly price increase is the one an admin set (PlanningSettingsService), never the
    // caller's, so Home, Reports and older app versions (which still send priceIncrease) agree.
    @GetMapping
    public Map<String, Object> forecast(@RequestParam(defaultValue = "" + ReplacementForecastService.DEFAULT_YEARS) int years,
                                        @RequestParam(defaultValue = "false") boolean items) {
        return replacementForecastService.forecast(years, planningSettings.priceIncreasePercent(), items, accessService.staffScope());
    }
}
