package com.sanjose.inventory.dto;

import lombok.Data;
import java.math.BigDecimal;
import java.time.LocalDate;

@Data
public class AssetRequest {
    private String propertyNumber;
    private String parNumber;       // YYYY-MM:SERIAL, e.g. 2026-07:H78JD80 — must match acquisitionDate's year-month
    // One entry per device — size must equal quantity, and quantity must equal
    // physicalCount. Every field on the request above is shared by all devices; an
    // entry may override any of them for that device. Each device is created as its
    // own asset. For quantity 1 this may be omitted (propertyNumber/parNumber above
    // are used). A blank propertyNumber is auto-generated; parNumber is required.
    private java.util.List<AssetUnitRequest> units;
    private String serialNumber;
    private String description;
    private Long categoryId;
    private Integer quantity;
    private LocalDate acquisitionDate;
    private BigDecimal unitValue;
    private Long officeId;
    private Long personnelId;
    private Long currentUserId;
    private Integer physicalCount;
    private String location;
    private String condition;       // SERVICEABLE | REPAIRABLE | UNSERVICEABLE
    private String lifecycleStatus; // REGISTERED | ASSIGNED | TRANSFERRED | UNDER_MAINTENANCE | DISPOSED | ARCHIVED
    private String qrCodePath;
    private String sha256Hash;
    private String remarks;
    private String specifications;
}
