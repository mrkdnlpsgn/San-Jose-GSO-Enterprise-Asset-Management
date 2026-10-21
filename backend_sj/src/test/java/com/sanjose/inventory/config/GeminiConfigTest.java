package com.sanjose.inventory.config;

import com.google.genai.errors.ApiException;
import com.google.genai.types.GenerateContentConfig;
import com.google.genai.types.GenerateContentResponse;
import com.google.genai.types.ThinkingConfig;
import com.google.genai.types.ThinkingLevel;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.ArrayList;
import java.util.List;
import java.util.function.Function;

import static org.junit.jupiter.api.Assertions.*;

class GeminiConfigTest {

    private static final String FAST = "gemini-3.5-flash-lite";
    private static final String SMART = "gemini-2.5-flash";

    private GeminiConfig config;
    private final List<String> called = new ArrayList<>();

    @BeforeEach
    void setUp() {
        config = new GeminiConfig();
        ReflectionTestUtils.setField(config, "enabled", true);
        ReflectionTestUtils.setField(config, "apiKey", "test-key");
        ReflectionTestUtils.setField(config, "fastModel", FAST);
        ReflectionTestUtils.setField(config, "smartModel", SMART);
    }

    // Calls the private generate(tier, what, call) with a fake Gemini that fails on the given models.
    private GenerateContentResponse generate(GeminiConfig.Tier tier, String... dailyQuotaUsedUp) {
        List<String> exhausted = List.of(dailyQuotaUsedUp);
        Function<String, GenerateContentResponse> call = model -> {
            called.add(model);
            if (exhausted.contains(model)) {
                throw new ApiException(429, "RESOURCE_EXHAUSTED", "Quota exceeded: GenerateRequestsPerDayPerProjectPerModel-FreeTier");
            }
            return GenerateContentResponse.builder().build();
        };
        return ReflectionTestUtils.invokeMethod(config, "generate", tier, "Test", call);
    }

    @Test
    void usesTheTiersModelFirst() {
        generate(GeminiConfig.Tier.FAST);
        generate(GeminiConfig.Tier.SMART);
        assertEquals(List.of(FAST, SMART), called);
    }

    @Test
    void fallsBackToTheOtherModelWhenTheQuotaIsUsedUp() {
        assertNotNull(generate(GeminiConfig.Tier.FAST, FAST));
        assertEquals(List.of(FAST, SMART), called);
        assertTrue(config.isAvailable(), "one model still has quota");

        // the used-up model is skipped from now on, not asked again
        called.clear();
        generate(GeminiConfig.Tier.FAST);
        assertEquals(List.of(SMART), called);
    }

    @Test
    void unavailableOnlyWhenBothModelsAreUsedUp() {
        IllegalStateException e = assertThrows(IllegalStateException.class,
            () -> generate(GeminiConfig.Tier.SMART, FAST, SMART));
        assertFalse(config.isAvailable());
        assertTrue(e.getMessage().contains("daily limit"), e.getMessage());
    }

    @Test
    void otherErrorsAreNotRetriedOnTheOtherModel() {
        Function<String, GenerateContentResponse> call = model -> {
            called.add(model);
            throw new ApiException(400, "INVALID_ARGUMENT", "bad request");
        };
        assertThrows(IllegalStateException.class,
            () -> ReflectionTestUtils.invokeMethod(config, "generate", GeminiConfig.Tier.FAST, "Test", call));
        assertEquals(List.of(FAST), called);
        assertTrue(config.isAvailable());
    }

    @Test
    void aRetiredModelFallsBackToTheOtherOne() {
        Function<String, GenerateContentResponse> call = model -> {
            called.add(model);
            if (model.equals(FAST)) throw new ApiException(404, "NOT_FOUND", "model is no longer available");
            return GenerateContentResponse.builder().build();
        };
        assertNotNull(ReflectionTestUtils.invokeMethod(config, "generate", GeminiConfig.Tier.FAST, "Test", call));
        assertEquals(List.of(FAST, SMART), called);
    }

    @Test
    void thinkingBudgetsBecomeLevelsOnNewerModels() {
        GenerateContentConfig off = GenerateContentConfig.builder().thinkingConfig(GeminiConfig.thinking(GeminiConfig.NO_THINKING)).build();
        GenerateContentConfig light = GenerateContentConfig.builder().thinkingConfig(GeminiConfig.thinking(GeminiConfig.LIGHT_THINKING)).build();

        // 2.5 keeps the budget it was given
        assertEquals(0, GeminiConfig.forModel("gemini-2.5-flash", off).thinkingConfig().flatMap(ThinkingConfig::thinkingBudget).orElseThrow());

        ThinkingConfig t = GeminiConfig.forModel("gemini-3.5-flash-lite", off).thinkingConfig().orElseThrow();
        assertTrue(t.thinkingBudget().isEmpty(), "no budget sent to Gemini 3");
        assertEquals(ThinkingLevel.Known.MINIMAL, t.thinkingLevel().orElseThrow().knownEnum());
        assertEquals(ThinkingLevel.Known.LOW, GeminiConfig.forModel("gemini-3.5-flash-lite", light)
            .thinkingConfig().orElseThrow().thinkingLevel().orElseThrow().knownEnum());
    }
}
