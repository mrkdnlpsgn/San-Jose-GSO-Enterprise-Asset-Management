package com.sanjose.inventory.dto;

import lombok.Data;

@Data
public class ArticleRequest {
    private Long categoryId;
    private String articleName;
}
