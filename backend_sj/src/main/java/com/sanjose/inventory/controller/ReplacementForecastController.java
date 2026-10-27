package com.sanjose.inventory.controller;

import com.sanjose.inventory.service.AccessService;
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

    @GetMapping
    public Map<String, Object> forecast(@RequestParam(defaultValue = "" + ReplacementForecastService.DEFAULT_YEARS) int years,
                                        @RequestParam(defaultValue = "" + ReplacementForecastService.DEFAULT_PRICE_INCREASE) double priceIncrease,
                                        @RequestParam(defaultValue = "false") boolean items) {
        return replacementForecastService.forecast(years, priceIncrease, items, accessService.staffScope());
    }
}
