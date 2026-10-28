package com.sanjose.inventory.config;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.google.genai.types.Content;
import com.google.genai.types.GenerateContentConfig;
import com.google.genai.types.Part;
import com.google.genai.types.Schema;
import com.google.genai.types.Type;
import com.sun.net.httpserver.HttpServer;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;

import java.net.InetSocketAddress;
import java.util.Map;
import java.util.concurrent.atomic.AtomicReference;

import static org.junit.jupiter.api.Assertions.*;

// The fallback AI against a fake OpenAI-style chat service on localhost.
class AiFallbackClientTest {

    private static final ObjectMapper JSON = new ObjectMapper();

    private HttpServer server;
    private final AtomicReference<JsonNode> received = new AtomicReference<>();
    private final AtomicReference<String> authorization = new AtomicReference<>();
    private volatile int status = 200;
    private volatile String answer = "Hello from the fallback";
    private AiFallbackClient client;

    @BeforeEach
    void setUp() throws Exception {
        server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        server.createContext("/v1/chat/completions", (ex) -> {
            received.set(JSON.readTree(ex.getRequestBody()));
            authorization.set(ex.getRequestHeaders().getFirst("Authorization"));
            byte[] out = JSON.writeValueAsBytes(Map.of("choices", java.util.List.of(
                Map.of("message", Map.of("role", "assistant", "content", answer)))));
            if (status == 429) ex.getResponseHeaders().add("retry-after", "30");
            ex.sendResponseHeaders(status, out.length);
            ex.getResponseBody().write(out);
            ex.close();
        });
        server.start();
        client = new AiFallbackClient();
        ReflectionTestUtils.setField(client, "apiKey", "test-key");
        ReflectionTestUtils.setField(client, "baseUrl", "http://127.0.0.1:" + server.getAddress().getPort() + "/v1/");
        ReflectionTestUtils.setField(client, "model", "text-model");
        ReflectionTestUtils.setField(client, "visionModel", "");
    }

    @AfterEach
    void tearDown() {
        server.stop(0);
    }

    @Test
    void offWithoutAKey() {
        ReflectionTestUtils.setField(client, "apiKey", "");
        assertFalse(client.isConfigured());
        assertFalse(client.isAvailable());
    }

    @Test
    void sendsTheSystemInstructionAndPromptAndReturnsTheText() {
        GenerateContentConfig config = GenerateContentConfig.builder()
            .systemInstruction(Content.fromParts(Part.fromText("You write maintenance summaries.")))
            .temperature(0.2f)
            .build();
        String text = client.generate("Test", Content.fromParts(Part.fromText("Summarize this.")), config).text();

        assertEquals("Hello from the fallback", text);
        assertEquals("Bearer test-key", authorization.get());
        JsonNode body = received.get();
        assertEquals("text-model", body.get("model").asText());
        assertEquals("system", body.at("/messages/0/role").asText());
        assertEquals("You write maintenance summaries.", body.at("/messages/0/content").asText());
        assertEquals("Summarize this.", body.at("/messages/1/content").asText());
        assertEquals(0.2, body.get("temperature").asDouble(), 0.001);
    }

    @Test
    void aJsonAnswerGetsTheSchemaAndLosesCodeFences() {
        answer = "```json\n{\"category\": \"ICT Equipment\"}\n```";
        Schema schema = Schema.builder().type(Type.Known.OBJECT)
            .properties(Map.of("category", Schema.builder().type(Type.Known.STRING).build())).build();
        GenerateContentConfig config = GenerateContentConfig.builder()
            .systemInstruction(Content.fromParts(Part.fromText("Pick a category.")))
            .responseMimeType("application/json").responseSchema(schema).build();

        String text = client.generate("Test", Content.fromParts(Part.fromText("Laptop")), config).text();

        assertEquals("{\"category\": \"ICT Equipment\"}", text);
        String system = received.get().at("/messages/0/content").asText();
        assertTrue(system.startsWith("Pick a category."), system);
        assertTrue(system.contains("JSON schema") && system.contains("category"), system);
    }

    @Test
    void aPhotoGoesToTheVisionModelAsADataUrl() {
        Content photo = Content.fromParts(Part.fromText("Read the label."), Part.fromBytes(new byte[] {1, 2, 3}, "image/png"));
        assertFalse(client.canAnswer(photo), "no vision model set");
        assertTrue(client.canAnswer(Content.fromParts(Part.fromText("text only"))));

        ReflectionTestUtils.setField(client, "visionModel", "vision-model");
        assertTrue(client.canAnswer(photo));
        client.generate("Test", photo, null);

        JsonNode body = received.get();
        assertEquals("vision-model", body.get("model").asText());
        assertEquals("Read the label.", body.at("/messages/0/content/0/text").asText());
        assertEquals("data:image/png;base64,AQID", body.at("/messages/0/content/1/image_url/url").asText());
    }

    @Test
    void photosCanGoToASecondService() throws Exception {
        // the text service is elsewhere; the vision model is on this (fake) one, with its own key
        HttpServer other = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        other.start();
        try {
            String here = (String) ReflectionTestUtils.getField(client, "baseUrl");
            ReflectionTestUtils.setField(client, "baseUrl", "http://127.0.0.1:" + other.getAddress().getPort() + "/v1");
            ReflectionTestUtils.setField(client, "visionBaseUrl", here);
            ReflectionTestUtils.setField(client, "visionApiKey", "vision-key");
            ReflectionTestUtils.setField(client, "visionModel", "vision-model");

            Content photo = Content.fromParts(Part.fromText("Read the label."), Part.fromBytes(new byte[] {1}, "image/jpeg"));
            assertEquals("Hello from the fallback", client.generate("Test", photo, null).text());
            assertEquals("Bearer vision-key", authorization.get());
            assertEquals("vision-model", received.get().get("model").asText());

            // a busy vision service pauses photos only, not text
            status = 429;
            assertThrows(IllegalStateException.class, () -> client.generate("Test", photo, null));
            assertFalse(client.canAnswer(photo));
            assertTrue(client.isAvailable());
        } finally {
            other.stop(0);
        }
    }

    @Test
    void onlyAVisionServiceSetUp() {
        ReflectionTestUtils.setField(client, "apiKey", "");
        ReflectionTestUtils.setField(client, "visionApiKey", "vision-key");
        ReflectionTestUtils.setField(client, "visionModel", "vision-model");
        assertTrue(client.isConfigured());
        assertFalse(client.isAvailable(), "no text service");
        assertTrue(client.canAnswer(Content.fromParts(Part.fromBytes(new byte[] {1}, "image/jpeg"))));
    }

    @Test
    void aRateLimitPausesTheFallback() {
        status = 429;
        IllegalStateException e = assertThrows(IllegalStateException.class,
            () -> client.generate("Test", Content.fromParts(Part.fromText("Hi")), null));
        assertTrue(e.getMessage().contains("busy"), e.getMessage());
        assertFalse(client.isAvailable(), "paused after a 429");
    }

    @Test
    void anErrorSaysTheBackupFailed() {
        status = 500;
        IllegalStateException e = assertThrows(IllegalStateException.class,
            () -> client.generate("Test", Content.fromParts(Part.fromText("Hi")), null));
        assertTrue(e.getMessage().contains("backup AI"), e.getMessage());
        assertTrue(client.isAvailable(), "a server error doesn't pause it");
    }

    @Test
    void unfence() {
        assertEquals("{\"a\":1}", AiFallbackClient.unfence("```json\n{\"a\":1}\n```"));
        assertEquals("{\"a\":1}", AiFallbackClient.unfence("  {\"a\":1} "));
    }

}
