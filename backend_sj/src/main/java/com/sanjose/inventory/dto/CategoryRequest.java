package com.sanjose.inventory.dto;

import lombok.Data;

@Data
public class CategoryRequest {
    private String categoryName;
    private String description;
    private Integer usefulLifeYears;
}
