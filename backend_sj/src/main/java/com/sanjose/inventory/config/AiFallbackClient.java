package com.sanjose.inventory.config;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ArrayNode;
import com.fasterxml.jackson.databind.node.ObjectNode;
import com.google.genai.types.Blob;
import com.google.genai.types.Candidate;
import com.google.genai.types.Content;
import com.google.genai.types.GenerateContentConfig;
import com.google.genai.types.GenerateContentResponse;
import com.google.genai.types.Part;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Base64;
import java.util.List;

// The AI used when Gemini can't answer (both models out of quota, or Google down): any service with
// an OpenAI-style chat API - Groq (the default, free tier), OpenRouter, Mistral, OpenAI... - set on
// the server with AI_FALLBACK_API_KEY, and optionally AI_FALLBACK_BASE_URL and AI_FALLBACK_MODEL.
// Off while no key is set. Requests with a photo go to AI_FALLBACK_VISION_MODEL, which may be on a
// second service (AI_FALLBACK_VISION_BASE_URL / AI_FALLBACK_VISION_API_KEY, e.g. OpenRouter, since
// Groq has no vision model); no vision model means photos have no fallback. It takes the same
// request the services build for Gemini and hands back a Gemini-shaped response, so the services
// don't change.
@Slf4j
@Component
public class AiFallbackClient {

    @Value("${ai.fallback.api-key:}")
    private String apiKey;

    @Value("${ai.fallback.base-url:https://api.groq.com/openai/v1}")
    private String baseUrl;

    @Value("${ai.fallback.model:openai/gpt-oss-120b}")
    private String model;

    // For requests with a photo (reading a label or PAR); none means photos have no fallback
    @Value("${ai.fallback.vision-model:}")
    private String visionModel;

    // The service the vision model is on, when not the one above; blank = the same
    @Value("${ai.fallback.vision-base-url:}")
    private String visionBaseUrl = "";

    @Value("${ai.fallback.vision-api-key:}")
    private String visionApiKey = "";

    private static final ObjectMapper JSON = new ObjectMapper();
    private final HttpClient http = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(10)).build();

    // A 429 pauses that service (text or vision, each on its own), so a busy spell isn't hammered
    private volatile Instant pausedUntil = Instant.EPOCH;
    private volatile Instant visionPausedUntil = Instant.EPOCH;

    private String visionKey() { return visionApiKey.isBlank() ? apiKey : visionApiKey; }
    private String visionUrl() { return visionBaseUrl.isBlank() ? baseUrl : visionBaseUrl; }

    // Either service set up
    public boolean isConfigured() {
        return !apiKey.isBlank() || (!visionModel.isBlank() && !visionKey().isBlank());
    }

    // The text service can answer now (what most AI features need)
    public boolean isAvailable() {
        return !apiKey.isBlank() && Instant.now().isAfter(pausedUntil);
    }

    // This request can be answered now: a photo by the vision service, the rest by the text one
    public boolean canAnswer(Content content) {
        if (!hasImage(content)) return isAvailable();
        return !visionModel.isBlank() && !visionKey().isBlank() && Instant.now().isAfter(visionPausedUntil);
    }

    public GenerateContentResponse generate(String what, Content content, GenerateContentConfig config) {
        boolean image = hasImage(content);
        String useModel = image ? visionModel : model;
        String url = image ? visionUrl() : baseUrl;
        try {
            HttpRequest req = HttpRequest.newBuilder(URI.create(url.replaceAll("/+$", "") + "/chat/completions"))
                .timeout(Duration.ofSeconds(90))
                .header("Authorization", "Bearer " + (image ? visionKey() : apiKey))
                .header("Content-Type", "application/json")
                .POST(HttpRequest.BodyPublishers.ofString(JSON.writeValueAsString(body(useModel, content, config))))
                .build();
            HttpResponse<String> res = http.send(req, HttpResponse.BodyHandlers.ofString());
            if (res.statusCode() == 429) {
                long wait = res.headers().firstValue("retry-after").map(AiFallbackClient::seconds).orElse(60L);
                Instant until = Instant.now().plusSeconds(Math.max(wait, 10));
                if (image) visionPausedUntil = until; else pausedUntil = until;
                log.warn("{}: fallback AI ({}) is rate-limited; not calling it until {}", what, useModel, until);
                throw new IllegalStateException("The AI assistant is busy right now. Please try again in a minute.");
            }
            if (res.statusCode() / 100 != 2) {
                log.error("{} failed on fallback {} (HTTP {}): {}", what, useModel, res.statusCode(), res.body());
                throw new IllegalStateException(what + " failed: the backup AI service answered " + res.statusCode() + ".");
            }
            String text = JSON.readTree(res.body()).path("choices").path(0).path("message").path("content").asText("");
            if (config != null && config.responseSchema().isPresent()) text = unfence(text);
            log.info("{} answered by the fallback AI ({})", what, useModel);
            return GenerateContentResponse.builder()
                .modelVersion(useModel)
                .candidates(List.of(Candidate.builder()
                    .content(Content.builder().role("model").parts(List.of(Part.fromText(text))).build())
                    .build()))
                .build();
        } catch (IllegalStateException e) {
            throw e;
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException(what + " was interrupted.", e);
        } catch (Exception e) {
            log.error("{} failed on fallback {}: {}", what, useModel, e.getMessage());
            throw new IllegalStateException(what + " failed: the backup AI service couldn't be reached.", e);
        }
    }

    // The Gemini request as a chat completion: the system instruction (plus, for a JSON answer, the
    // shape to follow - not every service takes a schema, so it is spelled out), then the user's
    // text and any photos as data URLs.
    private ObjectNode body(String useModel, Content content, GenerateContentConfig config) throws Exception {
        ObjectNode body = JSON.createObjectNode().put("model", useModel);
        ArrayNode messages = body.putArray("messages");

        StringBuilder system = new StringBuilder();
        if (config != null) {
            config.systemInstruction().ifPresent((c) -> system.append(textOf(c)));
            if (config.responseSchema().isPresent()) {
                system.append("\n\nReply with only a JSON object, no other text and no code fences, that follows this JSON schema:\n")
                    .append(config.responseSchema().get().toJson());
            } else if (config.responseMimeType().map("application/json"::equals).orElse(false)) {
                system.append("\n\nReply with only a JSON object, no other text and no code fences.");
            }
            config.temperature().ifPresent((t) -> body.put("temperature", t));
            config.maxOutputTokens().ifPresent((n) -> body.put("max_tokens", n));
        }
        if (!system.isEmpty()) messages.addObject().put("role", "system").put("content", system.toString().trim());

        ArrayNode parts = JSON.createArrayNode();
        for (Part p : content.parts().orElse(List.of())) {
            p.text().ifPresent((t) -> parts.addObject().put("type", "text").put("text", t));
            p.inlineData().flatMap(Blob::data).ifPresent((bytes) -> {
                String mime = p.inlineData().flatMap(Blob::mimeType).orElse("image/jpeg");
                parts.addObject().put("type", "image_url").putObject("image_url")
                    .put("url", "data:" + mime + ";base64," + Base64.getEncoder().encodeToString(bytes));
            });
        }
        ObjectNode user = messages.addObject().put("role", "user");
        // plain text as a string: some text-only models refuse the list form
        if (parts.size() == 1 && parts.get(0).has("text")) user.put("content", parts.get(0).get("text").asText());
        else user.set("content", parts);
        return body;
    }

    private static boolean hasImage(Content content) {
        return content.parts().orElse(List.of()).stream().anyMatch((p) -> p.inlineData().isPresent());
    }

    private static String textOf(Content c) {
        List<String> texts = new ArrayList<>();
        for (Part p : c.parts().orElse(List.of())) p.text().ifPresent(texts::add);
        return String.join("\n", texts);
    }

    // a JSON answer wrapped in ```json fences despite the instruction
    static String unfence(String text) {
        String t = text.trim();
        if (t.startsWith("```")) {
            t = t.replaceFirst("^```[a-zA-Z]*\\s*", "");
            int end = t.lastIndexOf("```");
            if (end >= 0) t = t.substring(0, end);
        }
        return t.trim();
    }

    private static long seconds(String v) {
        try { return (long) Math.ceil(Double.parseDouble(v)); } catch (NumberFormatException e) { return 60L; }
    }
}
