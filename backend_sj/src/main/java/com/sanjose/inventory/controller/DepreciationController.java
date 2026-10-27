package com.sanjose.inventory.controller;

import com.sanjose.inventory.service.AccessService;
import com.sanjose.inventory.service.DepreciationService;
import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.*;

import java.time.LocalDate;
import java.time.format.DateTimeParseException;
import java.util.Map;

// Straight-line depreciation schedule as of a date (default today), for Reports; the Home section
// uses /api/ai-insights/planning. Staff only see their own assets (AccessService.staffScope).
@RestController
@RequestMapping("/api/ai-insights/depreciation")
@RequiredArgsConstructor
public class DepreciationController {

    private final DepreciationService depreciationService;
    private final AccessService accessService;

    @GetMapping
    public Map<String, Object> schedule(@RequestParam(required = false) String asOf,
                                        @RequestParam(defaultValue = "false") boolean items) {
        return depreciationService.schedule(parse(asOf), items, accessService.staffScope());
    }

    // blank = today; anything else must be YYYY-MM-DD
    private static LocalDate parse(String asOf) {
        if (asOf == null || asOf.isBlank()) return null;
        try { return LocalDate.parse(asOf.trim()); }
        catch (DateTimeParseException e) { throw new IllegalArgumentException("Use a date like 2024-11-30 for asOf."); }
    }
}
