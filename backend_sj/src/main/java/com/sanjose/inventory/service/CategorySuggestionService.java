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
import com.sanjose.inventory.dto.CategorySuggestion;
import com.sanjose.inventory.entity.Category;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

@Slf4j
@Service
public class CategorySuggestionService {

    private static final String MODEL = "gemini-2.5-flash";
    private static final ObjectMapper OBJECT_MAPPER = new ObjectMapper();

    private final CategoryService categoryService;
    private final GeminiConfig geminiConfig;

    public CategorySuggestionService(CategoryService categoryService, GeminiConfig geminiConfig) {
        this.categoryService = categoryService;
        this.geminiConfig = geminiConfig;
    }

    private static final String SYSTEM_PROMPT = """
        You classify ICT and general equipment assets into one of a fixed set of categories for a \
        Philippine municipal government inventory system. Pick exactly one category from the provided \
        list that best matches the asset description. If nothing fits well, pick the closest reasonable \
        match — you must always choose one of the listed categories. Respond only with JSON matching the \
        given schema.""";

    public Category suggest(String description) {
        geminiConfig.requireConfigured();

        if (description == null || description.isBlank()) {
            throw new IllegalArgumentException("A description is required to suggest a category.");
        }

        List<Category> categories = categoryService.findAll(null);
        if (categories.isEmpty()) {
            throw new IllegalStateException("No categories exist yet to suggest from.");
        }

        Map<String, Category> byName = categories.stream()
            .collect(Collectors.toMap(Category::getCategoryName, c -> c, (a, b) -> a));

        String categoryList = categories.stream()
            .map(c -> "- " + c.getCategoryName()
                + (c.getDescription() != null && !c.getDescription().isBlank() ? ": " + c.getDescription() : ""))
            .collect(Collectors.joining("\n"));

        String prompt = "Asset description: " + description.trim() + "\n\nAvailable categories:\n" + categoryList;

        Schema schema = Schema.builder()
            .type(Type.Known.OBJECT)
            .properties(Map.of(
                "categoryName", Schema.builder()
                    .type(Type.Known.STRING)
                    .format("enum")
                    .enum_(byName.keySet().toArray(String[]::new))
                    .description("The single best-matching category name for this asset description.")
                    .build()))
            .required("categoryName")
            .build();

        Client client = geminiConfig.buildClient();

        GenerateContentConfig config = GenerateContentConfig.builder()
            .systemInstruction(Content.fromParts(Part.fromText(SYSTEM_PROMPT)))
            .responseMimeType("application/json")
            .responseSchema(schema)
            .build();

        GenerateContentResponse response;
        try {
            response = client.models.generateContent(MODEL, prompt, config);
        } catch (ApiException e) {
            log.error("Category suggestion request failed: {}", e.getMessage());
            throw geminiConfig.failure("AI category suggestion", e);
        }

        String json = response.text();
        if (json == null || json.isBlank()) {
            throw new IllegalStateException("The AI did not return a category suggestion.");
        }

        CategorySuggestion suggestion;
        try {
            suggestion = OBJECT_MAPPER.readValue(json, CategorySuggestion.class);
        } catch (Exception e) {
            log.error("Could not parse category suggestion response: {}", json);
            throw new IllegalStateException("Could not parse the AI response: " + e.getMessage(), e);
        }

        Category matched = byName.get(suggestion.categoryName());
        if (matched == null) {
            throw new IllegalStateException("AI suggested an unknown category: " + suggestion.categoryName());
        }
        return matched;
    }
}
