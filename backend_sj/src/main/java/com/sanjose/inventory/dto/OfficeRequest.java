package com.sanjose.inventory.dto;

import lombok.Data;

@Data
public class OfficeRequest {
    private String officeName;
    private Long headUserId;
    // null keeps the current code, blank clears it
    private String propertyCode;
}
