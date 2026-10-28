package com.sanjose.inventory.config;

import com.google.genai.Client;
import com.google.genai.errors.ApiException;
import com.google.genai.types.Content;
import com.google.genai.types.GenerateContentConfig;
import com.google.genai.types.GenerateContentResponse;
import com.google.genai.types.Part;
import com.google.genai.types.ThinkingConfig;
import com.google.genai.types.ThinkingLevel;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;
import java.time.format.DateTimeFormatter;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.function.Function;

@Slf4j
@Component
@RequiredArgsConstructor
public class GeminiConfig {

    // Asked when Gemini can't answer (see AiFallbackClient); off unless AI_FALLBACK_API_KEY is set
    private final AiFallbackClient fallback;

    // Gemini's free-tier daily quota resets at midnight US Pacific time.
    private static final ZoneId QUOTA_ZONE = ZoneId.of("America/Los_Angeles");
    private static final long MINUTE_BACKOFF_SECONDS = 60;

    @Value("${ai.recommendations.enabled:false}")
    private boolean enabled;

    @Value("${gemini.api-key:}")
    private String apiKey;

    // Two models, set on the server (Render env vars GEMINI_MODEL_FAST / GEMINI_MODEL_SMART):
    //   FAST  - the everyday, automatic work (summaries, justifications, recommendations, digest).
    //           A Flash-Lite model: far more free requests a day than Flash, so it can run on every change.
    //   SMART - work where a careful read matters more than volume (reading label photos, the
    //           dashboard period summary). Flash, about 20 a day on the free plan.
    // Each falls back to the other when its quota runs out, so AI keeps working while either has some left.
    public enum Tier { FAST, SMART }

    @Value("${gemini.model.fast:gemini-3.5-flash-lite}")
    private String fastModel;

    @Value("${gemini.model.smart:gemini-2.5-flash}")
    private String smartModel;

    // A model Google answered 429 for (quota used up): not called again until then, so nothing
    // keeps hammering a dead quota. Quotas are per model, so each model is paused on its own.
    private record Pause(Instant until, boolean forTheDay) {}
    private final Map<String, Pause> pauses = new ConcurrentHashMap<>();

    // On, with Gemini, the fallback AI or both
    public boolean isConfigured() {
        return enabled && (!apiKey.isBlank() || fallback.isConfigured());
    }

    private boolean geminiReady() {
        return !apiKey.isBlank() && (!isPaused(fastModel) || !isPaused(smartModel));
    }

    // Configured and at least one model not waiting out a quota limit.
    public boolean isAvailable() {
        return isConfigured() && unavailableMessage() == null;
    }

    private boolean isPaused(String model) {
        Pause p = pauses.get(model);
        return p != null && Instant.now().isBefore(p.until());
    }

    // Why AI can't be used right now, for the user - or null when it can (a Gemini model has quota
    // left, or the fallback AI can answer).
    public String unavailableMessage() {
        if (geminiReady() || fallback.isAvailable()) return null;
        if (apiKey.isBlank()) return "The AI assistant is busy right now. Please try again in a minute.";
        // both paused: report the one that comes back first
        Pause p = pauses.get(fastModel).until().isBefore(pauses.get(smartModel).until())
            ? pauses.get(fastModel) : pauses.get(smartModel);
        Instant until = p.until();
        if (!p.forTheDay()) return "The AI assistant is busy right now. Please try again in a minute.";
        String at = until.atZone(AppTime.ZONE).format(DateTimeFormatter.ofPattern("h:mm a"));
        boolean today = until.atZone(AppTime.ZONE).toLocalDate().equals(AppTime.today());
        return "The AI assistant has used up its daily limit on the free plan. It will work again "
            + (today ? "today" : "tomorrow") + " at about " + at + ".";
    }

    public void requireConfigured() {
        if (!isConfigured()) {
            throw new IllegalStateException(
                "AI features are not configured. Set GEMINI_API_KEY (or AI_FALLBACK_API_KEY) and AI_RECOMMENDATIONS_ENABLED=true.");
        }
        String unavailable = unavailableMessage();
        if (unavailable != null) throw new IllegalStateException(unavailable);
    }

    // Null when only the fallback AI is set up; generate() then goes straight to it.
    public Client buildClient() {
        return apiKey.isBlank() ? null : Client.builder().apiKey(apiKey).build();
    }

    // Asks Gemini, on the tier's model first and the other one if that model's quota is used up;
    // then, when neither can answer (quota used up, Google down), the fallback AI. A bad request
    // is thrown at once.
    public GenerateContentResponse generate(Client client, Tier tier, String what, String prompt,
                                            GenerateContentConfig config) {
        return generate(client, tier, what, Content.fromParts(Part.fromText(prompt)), config,
            model -> client.models.generateContent(model, prompt, forModel(model, config)));
    }

    public GenerateContentResponse generate(Client client, Tier tier, String what, Content content,
                                            GenerateContentConfig config) {
        return generate(client, tier, what, content, config,
            model -> client.models.generateContent(model, content, forModel(model, config)));
    }

    private GenerateContentResponse generate(Client client, Tier tier, String what, Content content,
                                             GenerateContentConfig config, Function<String, GenerateContentResponse> call) {
        IllegalStateException googleDown = null;
        if (client != null) {
            List<String> order = tier == Tier.FAST ? List.of(fastModel, smartModel) : List.of(smartModel, fastModel);
            for (String model : order.stream().distinct().toList()) {
                if (isPaused(model)) continue;
                try {
                    return call.apply(model);
                } catch (ApiException e) {
                    if (e.code() == 404) {
                        // model retired or not offered to this key: use the other one, and say so in the log
                        log.error("{}: model {} isn't available ({}); set GEMINI_MODEL_FAST / GEMINI_MODEL_SMART",
                            what, model, e.getMessage());
                        pauses.put(model, new Pause(Instant.now().plusSeconds(6 * 3600), true));
                        continue;
                    }
                    if (e.code() >= 500) {
                        // Google itself failing (overloaded, down): the fallback may still answer
                        log.error("{} failed on {}: {}", what, model, e.getMessage());
                        googleDown = new IllegalStateException(what + " failed: " + e.getMessage(), e);
                        break;
                    }
                    if (e.code() != 429) {
                        log.error("{} failed on {}: {}", what, model, e.getMessage());
                        throw new IllegalStateException(what + " failed: " + e.getMessage(), e);
                    }
                    pause(model, e);
                }
            }
        }
        if (fallback.isAvailable() && fallback.canRead(content)) {
            return fallback.generate(what, content, config);
        }
        if (googleDown != null) throw googleDown;
        String unavailable = unavailableMessage();
        throw new IllegalStateException(unavailable != null ? unavailable
            : "The AI assistant can't read photos right now. Please try again later.");
    }

    // Gemini 2.5 takes a thinking token budget; Gemini 3 and later take a thinking level instead
    // and reject a budget of 0 (they can't switch thinking off). The services set budgets, so for
    // newer models this turns them into the nearest level: none → minimal, light → low.
    static GenerateContentConfig forModel(String model, GenerateContentConfig config) {
        if (config == null || model.startsWith("gemini-2")) return config;
        Integer budget = config.thinkingConfig().flatMap(ThinkingConfig::thinkingBudget).orElse(null);
        if (budget == null) return config;
        ThinkingLevel.Known level = budget <= NO_THINKING ? ThinkingLevel.Known.MINIMAL
            : budget <= LIGHT_THINKING ? ThinkingLevel.Known.LOW
            : ThinkingLevel.Known.MEDIUM;
        return config.toBuilder().thinkingConfig(ThinkingConfig.builder().thinkingLevel(level).build()).build();
    }

    // gemini-2.5-flash "thinks" before answering by default, which is most of the wait (about 14s
    // for a recommendation). A token cap keeps answers fast; 0 turns thinking off for simple writing.
    public static final int NO_THINKING = 0;
    public static final int LIGHT_THINKING = 1024;

    public static ThinkingConfig thinking(int budgetTokens) {
        return ThinkingConfig.builder().thinkingBudget(budgetTokens).build();
    }

    // A 429 pauses that model: until the daily reset for a used-up daily quota, a minute for a busy spell.
    private void pause(String model, ApiException e) {
        boolean forTheDay = String.valueOf(e.getMessage()).contains("PerDay");
        Instant until = forTheDay
            ? LocalDate.now(QUOTA_ZONE).plusDays(1).atStartOfDay(QUOTA_ZONE).toInstant()
            : Instant.now().plusSeconds(MINUTE_BACKOFF_SECONDS);
        pauses.put(model, new Pause(until, forTheDay));
        log.warn("Gemini quota hit on {} ({}); not calling it until {}", model, forTheDay ? "daily" : "per-minute", until);
    }
}
