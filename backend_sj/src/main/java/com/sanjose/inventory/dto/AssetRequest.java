package com.sanjose.inventory.dto;

import lombok.Data;
import java.math.BigDecimal;
import java.time.LocalDate;

@Data
public class AssetRequest {
    private String propertyNumber;
    private String serialNumber;
    private String description;
    private Long categoryId;
    private Integer quantity;
    private LocalDate acquisitionDate;
    private BigDecimal unitValue;
    private Long officeId;
    private String accountablePerson;
    private Integer physicalCount;
    private String location;
    private String condition;       // SERVICEABLE | REPAIRABLE | UNSERVICEABLE
    private String lifecycleStatus; // REGISTERED | ASSIGNED | TRANSFERRED | UNDER_MAINTENANCE | DISPOSED | ARCHIVED
    private String qrCodePath;
    private String sha256Hash;
    private String remarks;
}
