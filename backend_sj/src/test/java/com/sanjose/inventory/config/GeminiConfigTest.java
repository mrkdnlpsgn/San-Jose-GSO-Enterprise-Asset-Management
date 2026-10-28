package com.sanjose.inventory.config;

import com.google.genai.Client;
import com.google.genai.errors.ApiException;
import com.google.genai.types.Content;
import com.google.genai.types.GenerateContentConfig;
import com.google.genai.types.GenerateContentResponse;
import com.google.genai.types.Part;
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
    private static final Content PROMPT = Content.fromParts(Part.fromText("Hello"));
    private static final Content PHOTO = Content.fromParts(Part.fromText("Read this"), Part.fromBytes(new byte[] {1, 2, 3}, "image/jpeg"));

    // A fallback AI that answers "fallback" when turned on, and remembers being asked
    static class FakeFallback extends AiFallbackClient {
        boolean on;
        boolean vision = true;
        int asked;
        @Override public boolean isConfigured() { return on; }
        @Override public boolean isAvailable() { return on; }
        @Override public boolean canRead(Content content) { return vision || content.parts().orElseThrow().stream().noneMatch(p -> p.inlineData().isPresent()); }
        @Override public GenerateContentResponse generate(String what, Content content, GenerateContentConfig config) {
            asked++;
            return GenerateContentResponse.builder().modelVersion("fallback").build();
        }
    }

    private FakeFallback fallback;
    private GeminiConfig config;
    private Client client;
    private final List<String> called = new ArrayList<>();

    @BeforeEach
    void setUp() {
        fallback = new FakeFallback();
        config = new GeminiConfig(fallback);
        ReflectionTestUtils.setField(config, "enabled", true);
        ReflectionTestUtils.setField(config, "apiKey", "test-key");
        ReflectionTestUtils.setField(config, "fastModel", FAST);
        ReflectionTestUtils.setField(config, "smartModel", SMART);
        client = config.buildClient();
    }

    private GenerateContentResponse call(GeminiConfig.Tier tier, Content content, Function<String, GenerateContentResponse> gemini) {
        return ReflectionTestUtils.invokeMethod(config, "generate", client, tier, "Test", content, null, gemini);
    }

    // Calls the private generate with a fake Gemini that fails on the given models.
    private GenerateContentResponse generate(GeminiConfig.Tier tier, String... dailyQuotaUsedUp) {
        return generate(tier, PROMPT, dailyQuotaUsedUp);
    }

    private GenerateContentResponse generate(GeminiConfig.Tier tier, Content content, String... dailyQuotaUsedUp) {
        List<String> exhausted = List.of(dailyQuotaUsedUp);
        return call(tier, content, model -> {
            called.add(model);
            if (exhausted.contains(model)) {
                throw new ApiException(429, "RESOURCE_EXHAUSTED", "Quota exceeded: GenerateRequestsPerDayPerProjectPerModel-FreeTier");
            }
            return GenerateContentResponse.builder().modelVersion(model).build();
        });
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
        fallback.on = true;
        assertThrows(IllegalStateException.class, () -> call(GeminiConfig.Tier.FAST, PROMPT, model -> {
            called.add(model);
            throw new ApiException(400, "INVALID_ARGUMENT", "bad request");
        }));
        assertEquals(List.of(FAST), called);
        assertEquals(0, fallback.asked, "a bad request isn't the fallback's to answer");
        assertTrue(config.isAvailable());
    }

    @Test
    void aRetiredModelFallsBackToTheOtherOne() {
        assertNotNull(call(GeminiConfig.Tier.FAST, PROMPT, model -> {
            called.add(model);
            if (model.equals(FAST)) throw new ApiException(404, "NOT_FOUND", "model is no longer available");
            return GenerateContentResponse.builder().build();
        }));
        assertEquals(List.of(FAST, SMART), called);
    }

    @Test
    void theFallbackAnswersWhenBothGeminiModelsAreUsedUp() {
        fallback.on = true;
        GenerateContentResponse r = generate(GeminiConfig.Tier.FAST, FAST, SMART);
        assertEquals("fallback", r.modelVersion().orElseThrow());
        assertEquals(1, fallback.asked);
        assertTrue(config.isAvailable(), "the fallback keeps AI available");
        assertNull(config.unavailableMessage());

        // with both Gemini models paused, the next request goes straight to the fallback
        called.clear();
        generate(GeminiConfig.Tier.SMART);
        assertTrue(called.isEmpty());
        assertEquals(2, fallback.asked);
    }

    @Test
    void theFallbackAnswersWhenGoogleIsDown() {
        fallback.on = true;
        GenerateContentResponse r = call(GeminiConfig.Tier.FAST, PROMPT, model -> {
            called.add(model);
            throw new ApiException(503, "UNAVAILABLE", "The model is overloaded");
        });
        assertEquals("fallback", r.modelVersion().orElseThrow());
        assertEquals(List.of(FAST), called);
    }

    @Test
    void googleDownWithoutAFallbackStillFails() {
        assertThrows(IllegalStateException.class, () -> call(GeminiConfig.Tier.FAST, PROMPT, model -> {
            throw new ApiException(503, "UNAVAILABLE", "The model is overloaded");
        }));
    }

    @Test
    void aPhotoNeedsAFallbackThatCanSee() {
        fallback.on = true;
        fallback.vision = false;
        IllegalStateException e = assertThrows(IllegalStateException.class,
            () -> generate(GeminiConfig.Tier.SMART, PHOTO, FAST, SMART));
        assertEquals(0, fallback.asked);
        assertTrue(e.getMessage().contains("photos"), e.getMessage());
    }

    @Test
    void onlyTheFallbackSetUp() {
        ReflectionTestUtils.setField(config, "apiKey", "");
        assertNull(config.buildClient());
        assertFalse(config.isConfigured());
        fallback.on = true;
        assertTrue(config.isConfigured());
        client = null;
        assertEquals("fallback", call(GeminiConfig.Tier.FAST, PROMPT, model -> fail("Gemini isn't set up")).modelVersion().orElseThrow());
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
