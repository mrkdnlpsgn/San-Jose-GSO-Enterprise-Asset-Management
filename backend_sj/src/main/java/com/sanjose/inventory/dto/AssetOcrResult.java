package com.sanjose.inventory.dto;

import com.fasterxml.jackson.annotation.JsonPropertyDescription;

// Response for POST /api/assets/scan-label — fields read off a photo of an
// asset tag/sticker or a property document (e.g. a Property Acknowledgment
// Receipt listing technical specifications), meant to pre-fill the Add Asset
// form for the user to review/correct, not to be saved as-is.
public record AssetOcrResult(
    @JsonPropertyDescription("The device/equipment name or type as printed on the label or document, "
        + "including brand/model if shown, e.g. \"Dell Inspiron 15 3520 Laptop Computer\". Null if not legible.")
    String description,

    @JsonPropertyDescription("The serial number (S/N) printed on the label or document, exactly as shown. "
        + "Null if not present or not legible.")
    String serialNumber,

    @JsonPropertyDescription("The technical specifications section, if present (e.g. under a \"Technical "
        + "Specifications:\" heading on a Property Acknowledgment Receipt or similar document) — one spec per "
        + "line, formatted as \"Label: Value\" exactly as printed (e.g. \"Processor: Core i7\", \"Memory: 16 GB\", "
        + "\"Engine Type: V6\"). Preserve the document's own labels and order; do not invent or infer values that "
        + "aren't legibly printed. Null if the photo has no such section (e.g. a plain device sticker with just a "
        + "name and serial number).")
    String specifications
) {}
