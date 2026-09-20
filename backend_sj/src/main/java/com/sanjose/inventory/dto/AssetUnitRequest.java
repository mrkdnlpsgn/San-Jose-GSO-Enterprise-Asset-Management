package com.sanjose.inventory.dto;

import lombok.Data;
import java.math.BigDecimal;
import java.time.LocalDate;

// One device in a multi-device create/update. Property Number and PAR Number identify
// the device; every other field is an optional override — null/blank means "same as
// the shared value on the parent AssetRequest".
@Data
public class AssetUnitRequest {
    private String propertyNumber;
    private String parNumber;
    private String serialNumber;
    private String specifications;
    private String remarks;
    private BigDecimal unitValue;
    private LocalDate acquisitionDate;
    private Long officeId;
    private String location;
    private Long personnelId;
    private Long currentUserId;
    private String condition; // SERVICEABLE | REPAIRABLE | UNSERVICEABLE
}
