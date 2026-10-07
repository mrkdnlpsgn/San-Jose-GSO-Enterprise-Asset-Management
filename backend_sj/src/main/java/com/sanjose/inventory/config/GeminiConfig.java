package com.sanjose.inventory.config;

import com.google.genai.Client;
import com.google.genai.errors.ApiException;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;
import java.time.format.DateTimeFormatter;

@Slf4j
@Component
public class GeminiConfig {

    // Gemini's free-tier daily quota resets at midnight US Pacific time.
    private static final ZoneId QUOTA_ZONE = ZoneId.of("America/Los_Angeles");
    private static final long MINUTE_BACKOFF_SECONDS = 60;

    @Value("${ai.recommendations.enabled:false}")
    private boolean enabled;

    @Value("${gemini.api-key:}")
    private String apiKey;

    // Set when Google answers 429 (quota used up): no AI calls until then, so nothing keeps
    // hammering a dead quota and every screen gets a clear message straight away.
    private volatile Instant blockedUntil;
    private volatile boolean blockedForTheDay;

    public boolean isConfigured() {
        return enabled && !apiKey.isBlank();
    }

    // Configured and not waiting out a quota limit.
    public boolean isAvailable() {
        return isConfigured() && unavailableMessage() == null;
    }

    // Why AI can't be used right now, for the user — or null when it can.
    public String unavailableMessage() {
        Instant until = blockedUntil;
        if (until == null || !Instant.now().isBefore(until)) return null;
        if (!blockedForTheDay) return "The AI assistant is busy right now. Please try again in a minute.";
        String at = until.atZone(AppTime.ZONE).format(DateTimeFormatter.ofPattern("h:mm a"));
        boolean today = until.atZone(AppTime.ZONE).toLocalDate().equals(AppTime.today());
        return "The AI assistant has used up its daily limit on the free plan. It will work again "
            + (today ? "today" : "tomorrow") + " at about " + at + ".";
    }

    public void requireConfigured() {
        if (!isConfigured()) {
            throw new IllegalStateException(
                "AI features are not configured. Set GEMINI_API_KEY and AI_RECOMMENDATIONS_ENABLED=true.");
        }
        String unavailable = unavailableMessage();
        if (unavailable != null) throw new IllegalStateException(unavailable);
    }

    public Client buildClient() {
        return Client.builder().apiKey(apiKey).build();
    }

    // Turns a failed Gemini call into the exception the services throw. A 429 also starts the
    // pause above: until the daily reset for a used-up daily quota, a minute for a busy spell.
    public IllegalStateException failure(String what, ApiException e) {
        if (e.code() == 429) {
            String detail = String.valueOf(e.getMessage());
            blockedForTheDay = detail.contains("PerDay");
            blockedUntil = blockedForTheDay
                ? LocalDate.now(QUOTA_ZONE).plusDays(1).atStartOfDay(QUOTA_ZONE).toInstant()
                : Instant.now().plusSeconds(MINUTE_BACKOFF_SECONDS);
            log.warn("Gemini quota hit ({}); pausing AI calls until {}", blockedForTheDay ? "daily" : "per-minute", blockedUntil);
            return new IllegalStateException(unavailableMessage(), e);
        }
        return new IllegalStateException(what + " failed: " + e.getMessage(), e);
    }
}
