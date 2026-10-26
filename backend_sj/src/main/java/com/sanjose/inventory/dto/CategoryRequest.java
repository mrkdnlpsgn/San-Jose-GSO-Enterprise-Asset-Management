package com.sanjose.inventory.dto;

import lombok.Data;

@Data
public class CategoryRequest {
    private String categoryName;
    private String description;
    private Integer usefulLifeYears;
    // null keeps the current code, blank clears it
    private String propertyCode;
}
