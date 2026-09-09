package com.sanjose.inventory.dto;

import lombok.Data;

// Mirrors the columns of the Excel export/import template. Everything comes in
// as a raw string (spreadsheet cells, same as the client-side parsing the
// existing Equipment import already does) — AssetService.bulkImport() parses
// and validates each field per row, so one bad row can't abort the batch.
@Data
public class AssetImportRow {
    private String description;
    private String categoryName;
    private String quantity;
    private String physicalCount;
    private String acquisitionDate; // yyyy-MM-dd
    private String unitValue;
    private String officeName;
    private String accountablePerson;
    private String location;
    private String condition;       // SERVICEABLE | REPAIRABLE | UNSERVICEABLE
    private String remarks;
}
