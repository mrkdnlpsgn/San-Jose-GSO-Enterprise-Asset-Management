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

// Reads a photo of either a physical asset tag/sticker (affixed to a laptop,
// monitor, printer, etc.) or a property document (e.g. a Property
// Acknowledgment Receipt / PAR listing technical specifications) via Gemini
// vision, and extracts whatever's legibly printed — device name, serial
// number, and technical specifications. Purely a pre-fill aid for the Add
// Asset form; the image is never persisted, and every extracted field is
// reviewed/editable by the user before anything is saved.
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
        You are reading a photo of either (a) a physical asset/equipment identification label or \
        manufacturer sticker affixed to a laptop, monitor, printer, or similar equipment, or (b) a \
        property document such as a Property Acknowledgment Receipt (PAR) that lists a device's \
        brand, model, serial number, and a "Technical Specifications" section (e.g. Processor, \
        Memory, Storage, Display, Operating System, or for other equipment types things like Engine \
        Type, Plate Number, Power Rating, etc.).

        Extract:
        - description: the device/equipment name or type, including brand/model if shown.
        - serialNumber: the serial number (S/N), exactly as printed.
        - specifications: if the photo has a technical-specifications section or itemized list of \
        specs, transcribe it as one spec per line in "Label: Value" format, exactly as printed, \
        preserving the document's own labels and order. Null if there is no such section (e.g. a \
        plain sticker with just a name and serial number).

        Do not guess, infer, normalize, or add anything that isn't legibly printed. If a field isn't \
        present or isn't legible, return null for it rather than guessing. Respond only with JSON \
        matching the given schema.""";

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
            Part.fromText("Extract the device name, serial number, and technical specifications "
                + "(if any) from this photo."),
            Part.fromBytes(imageBytes, contentType));

        Schema schema = Schema.builder()
            .type(Type.Known.OBJECT)
            .properties(Map.of(
                "description", Schema.builder()
                    .type(Type.Known.STRING)
                    .nullable(true)
                    .description("The device/equipment name or type as printed, including brand/model "
                        + "if shown, e.g. \"Dell Inspiron 15 3520 Laptop Computer\". Null if not legible.")
                    .build(),
                "serialNumber", Schema.builder()
                    .type(Type.Known.STRING)
                    .nullable(true)
                    .description("The serial number (S/N) printed on the label or document, exactly as "
                        + "shown. Null if not present or not legible.")
                    .build(),
                "specifications", Schema.builder()
                    .type(Type.Known.STRING)
                    .nullable(true)
                    .description("The technical specifications section, if present — one spec per line "
                        + "as \"Label: Value\" exactly as printed (e.g. \"Processor: Core i7\", "
                        + "\"Engine Type: V6\"), preserving the document's own labels and order. Null if "
                        + "the photo has no such section.")
                    .build()))
            .required("description", "serialNumber", "specifications")
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
            throw new IllegalStateException("Couldn't read that photo right now: " + e.getMessage(), e);
        }

        String json = response.text();
        if (json == null || json.isBlank()) {
            throw new IllegalStateException(
                "Couldn't read that photo clearly — try a closer, well-lit photo, or enter details manually.");
        }
        try {
            return OBJECT_MAPPER.readValue(json, AssetOcrResult.class);
        } catch (Exception e) {
            log.error("Could not parse OCR response: {}", json);
            throw new IllegalStateException("Could not parse the scan result: " + e.getMessage(), e);
        }
    }
}
