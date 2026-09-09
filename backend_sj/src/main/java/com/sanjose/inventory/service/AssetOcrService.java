package com.sanjose.inventory.service;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.google.genai.Client;
import com.google.genai.errors.ApiException;
import com.google.genai.types.Content;
import com.google.genai.types.GenerateContentConfig;
import com.google.genai.types.GenerateContentResponse;
import com.google.genai.types.Part;
import com.google.genai.types.Schema;
import com.google.genai.types.Type;
import com.sanjose.inventory.config.GeminiConfig;
import com.sanjose.inventory.dto.AssetOcrResult;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.web.multipart.MultipartFile;

import java.io.IOException;
import java.util.Map;
import java.util.Set;

// Reads an asset tag/sticker photo (the kind affixed to laptops, monitors,
// etc.) via Gemini vision and extracts whatever's legibly printed — device
// name and serial number. Purely a pre-fill aid for the Add Asset form; the
// image is never persisted, and every extracted field is reviewed/editable
// by the user before anything is saved.
@Slf4j
@Service
@RequiredArgsConstructor
public class AssetOcrService {

    private static final String MODEL = "gemini-2.5-flash";
    private static final ObjectMapper OBJECT_MAPPER = new ObjectMapper();
    private static final Set<String> ACCEPTED_CONTENT_TYPES =
        Set.of("image/jpeg", "image/png", "image/webp", "image/heic", "image/heif");

    private final GeminiConfig geminiConfig;

    private static final String SYSTEM_PROMPT = """
        You are reading a physical asset/equipment identification label or manufacturer sticker \
        (e.g. affixed to a laptop, monitor, printer, or similar equipment) from a photo — not a \
        document or form. Extract only the device name/type and the serial number, exactly as \
        printed. Do not guess, infer, or normalize anything that isn't legibly printed on the \
        label itself. If a field isn't present or isn't legible, return null for it rather than \
        guessing. Respond only with JSON matching the given schema.""";

    public AssetOcrResult scan(MultipartFile file) {
        geminiConfig.requireConfigured();

        if (file == null || file.isEmpty()) {
            throw new IllegalArgumentException("No image was provided.");
        }
        String contentType = file.getContentType();
        if (contentType == null || !ACCEPTED_CONTENT_TYPES.contains(contentType.toLowerCase())) {
            throw new IllegalArgumentException("Only JPEG, PNG, WEBP, or HEIC images are allowed.");
        }

        byte[] imageBytes;
        try {
            imageBytes = file.getBytes();
        } catch (IOException e) {
            throw new IllegalStateException("Could not read the uploaded image: " + e.getMessage(), e);
        }

        return requestExtraction(imageBytes, contentType);
    }

    private AssetOcrResult requestExtraction(byte[] imageBytes, String contentType) {
        Client client = geminiConfig.buildClient();

        Content content = Content.fromParts(
            Part.fromText("Extract the device name and serial number from this asset label photo."),
            Part.fromBytes(imageBytes, contentType));

        Schema schema = Schema.builder()
            .type(Type.Known.OBJECT)
            .properties(Map.of(
                "description", Schema.builder()
                    .type(Type.Known.STRING)
                    .nullable(true)
                    .description("The device/equipment name or type as printed on the label, "
                        + "e.g. \"Dell Latitude 5440 Laptop\". Null if not legible.")
                    .build(),
                "serialNumber", Schema.builder()
                    .type(Type.Known.STRING)
                    .nullable(true)
                    .description("The serial number (S/N) printed on the label, exactly as shown. "
                        + "Null if not present or not legible.")
                    .build()))
            .required("description", "serialNumber")
            .build();

        GenerateContentConfig config = GenerateContentConfig.builder()
            .systemInstruction(Content.fromParts(Part.fromText(SYSTEM_PROMPT)))
            .responseMimeType("application/json")
            .responseSchema(schema)
            .build();

        GenerateContentResponse response;
        try {
            response = client.models.generateContent(MODEL, content, config);
        } catch (ApiException e) {
            log.error("Asset label OCR request failed: {}", e.getMessage());
            throw new IllegalStateException("Couldn't read that label right now: " + e.getMessage(), e);
        }

        String json = response.text();
        if (json == null || json.isBlank()) {
            throw new IllegalStateException(
                "Couldn't read that label clearly — try a closer, well-lit photo, or enter details manually.");
        }
        try {
            return OBJECT_MAPPER.readValue(json, AssetOcrResult.class);
        } catch (Exception e) {
            log.error("Could not parse OCR response: {}", json);
            throw new IllegalStateException("Could not parse the label scan result: " + e.getMessage(), e);
        }
    }
}
