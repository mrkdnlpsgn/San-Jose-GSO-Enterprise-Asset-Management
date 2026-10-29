package com.sanjose.inventory.service;

import com.google.genai.Client;
import com.google.genai.types.Content;
import com.google.genai.types.GenerateContentConfig;
import com.google.genai.types.GenerateContentResponse;
import com.google.genai.types.Part;
import com.sanjose.inventory.config.GeminiConfig;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

// Home's "Budget & Planning" section (admins only): the replacement forecast, the repair and
// maintenance spending forecast and the depreciation totals of every asset on hand, with ONE AI
// summary covering all three, so the section costs one Gemini request instead of three. The summary is kept and returned with the numbers while they
// are unchanged; opening Home never calls Gemini, only pressing Generate does.
@Service
@RequiredArgsConstructor
public class PlanningInsightService {

    private final ReplacementForecastService replacementForecastService;
    private final DepreciationService depreciationService;
    private final MaintenanceForecastService maintenanceForecastService;
    private final GeminiConfig geminiConfig;

    private record CachedSummary(String factsJson, String summary) {}
    private volatile CachedSummary cached;

    public Map<String, Object> planning() {
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("replacement", replacementForecastService.forecast(
            ReplacementForecastService.DEFAULT_YEARS, ReplacementForecastService.DEFAULT_PRICE_INCREASE, false, null));
        out.put("maintenance", maintenanceForecastService.forecast(MaintenanceForecastService.DEFAULT_PRICE_INCREASE, null));
        out.put("depreciation", depreciationService.schedule(null, false, null));
        CachedSummary c = cached;
        if (c != null && c.factsJson().equals(factsJson(out))) out.put("summary", c.summary());
        return out;
    }

    public Map<String, Object> summarize(boolean refresh) {
        geminiConfig.requireConfigured();
        Map<String, Object> out = planning();
        String facts = factsJson(out);
        CachedSummary c = cached;
        String summary;
        if (!refresh && c != null && c.factsJson().equals(facts)) {
            summary = c.summary();
        } else {
            summary = requestSummary(facts);
            cached = new CachedSummary(facts, summary);
        }
        out.put("summary", summary);
        return out;
    }

    // What Gemini sees: the totals and the top few categories/offices, not every per-year split.
    @SuppressWarnings("unchecked")
    private static String factsJson(Map<String, Object> planning) {
        Map<String, Object> r = (Map<String, Object>) planning.get("replacement");
        Map<String, Object> d = (Map<String, Object>) planning.get("depreciation");

        Map<String, Object> replacement = new LinkedHashMap<>();
        for (String k : List.of("asOf", "years", "priceIncreasePercent", "total", "buckets")) replacement.put(k, r.get(k));
        replacement.put("topCategories", top((List<Map<String, Object>>) r.get("byCategory"), "buckets"));
        replacement.put("topOffices", top((List<Map<String, Object>>) r.get("topOffices"), null));

        Map<String, Object> depreciation = new LinkedHashMap<>();
        for (String k : List.of("asOf", "residualRatePercent", "total")) depreciation.put(k, d.get(k));
        depreciation.put("topCategoriesByDepreciation", top((List<Map<String, Object>>) d.get("byCategory"), null));

        Map<String, Object> m = (Map<String, Object>) planning.get("maintenance");
        Map<String, Object> maintenance = new LinkedHashMap<>();
        for (String k : List.of("years", "forecast", "trend", "priceIncreasePercent", "averageCostPerRepair", "limitedHistory")) {
            maintenance.put(k, m.get(k));
        }
        maintenance.put("topCategories", top((List<Map<String, Object>>) m.get("byCategory"), "perYear"));

        Map<String, Object> facts = new LinkedHashMap<>();
        facts.put("replacementForecast", replacement);
        facts.put("maintenanceSpending", maintenance);
        facts.put("depreciation", depreciation);
        // Only when something was left out; an empty list still tempts the AI to mention it.
        if (r.get("excluded") instanceof Map<?, ?> ex && ex.get("noExpectedLife") instanceof List<?> l && !l.isEmpty()) {
            facts.put("categoriesWithNoExpectedLife", l);
        }
        return LifecycleInsightService.toJson(facts);
    }

    private static List<Map<String, Object>> top(List<Map<String, Object>> rows, String drop) {
        if (rows == null) return List.of();
        return rows.stream().limit(5).map(m -> {
            Map<String, Object> copy = new LinkedHashMap<>(m);
            if (drop != null) copy.remove(drop);
            return copy;
        }).toList();
    }

    private static final String SYSTEM_PROMPT = """
        You write a short plain-English budget note for the staff and head of the General Services \
        Office of a Philippine municipal government. They are property custodians, not accountants: \
        say "what the assets are worth today" instead of "book value", "value lost this year" instead \
        of "depreciation expense", and "used longer than expected" instead of "past their expected \
        life"; you may give the official term once in brackets. You are given pre-computed facts (JSON) about the government \
        property on hand: (1) a replacement forecast: assets due for replacement now ("NOW" = already \
        past their expected life, or unserviceable and awaiting disposal) and in each coming year, \
        with the estimated replacement cost including a yearly price increase of priceIncreasePercent; \
        (2) repair and maintenance spending: the cost of each of the last full years and of this year \
        so far (the entry with soFar true is not a full year, never compare it with full years), next \
        year's estimate (forecast) with its trend (RISING, FALLING or STEADY) and the categories that \
        cost most to keep running; \
        (3) straight-line depreciation as of today: total cost, accumulated depreciation, book value, \
        depreciation expense so far this year, and how many assets are fully depreciated (only the 5% \
        residual value is left). Use only those numbers, never invent figures. In 5-7 short sentences: \
        state how many assets need replacing now and what that costs, name the coming year with the \
        highest replacement cost, name the categories (and offices) that drive most of the cost, then \
        give next year's estimated repair and maintenance budget, whether it is rising or falling and \
        which category costs most to repair (if limitedHistory is true, say the estimate rests on \
        little history), then give the book value against the total cost and the depreciation expense \
        so far this year, and mention the fully depreciated assets. If repairable assets are among those due, say repairing \
        some may delay part of the cost. If categoriesWithNoExpectedLife is given, say those assets are \
        not counted. Money is in Philippine pesos (write it as PHP, rounded to the nearest thousand or \
        million). Plain text only: start directly with the first sentence, with no title, date, \
        greeting or sign-off, and no markdown, bullet points or headers.""";

    private String requestSummary(String factsJson) {
        Client client = geminiConfig.buildClient();
        GenerateContentConfig config = GenerateContentConfig.builder()
            .thinkingConfig(GeminiConfig.thinking(GeminiConfig.NO_THINKING))
            .systemInstruction(Content.fromParts(Part.fromText(SYSTEM_PROMPT)))
            .build();
        GenerateContentResponse response = geminiConfig.generate(
            client, GeminiConfig.Tier.SMART, "AI budget and planning summary", "Facts:\n" + factsJson, config);
        String text = response.text();
        if (text == null || text.isBlank()) throw new IllegalStateException("The AI did not return a summary.");
        return text.trim();
    }
}
