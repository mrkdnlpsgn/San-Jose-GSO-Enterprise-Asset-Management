package com.sanjose.inventory.dto;

import com.fasterxml.jackson.annotation.JsonPropertyDescription;

// Response for POST /api/assets/scan-label — fields read off a photo of an
// asset tag/sticker, meant to pre-fill the Add Asset form for the user to
// review/correct, not to be saved as-is.
public record AssetOcrResult(
    @JsonPropertyDescription("The device/equipment name or type as printed on the label, e.g. \"Dell Latitude 5440 Laptop\". Null if not legible.")
    String description,

    @JsonPropertyDescription("The serial number (S/N) printed on the label, exactly as shown. Null if not present or not legible.")
    String serialNumber
) {}
