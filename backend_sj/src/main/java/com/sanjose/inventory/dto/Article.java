package com.sanjose.inventory.dto;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

// The kind of item within a category (Category: ICT Equipment, Article: Laptop), as the
// ARTICLE column of the Report on the Physical Count of PPE. Not a JPA entity: the table is
// created by ArticleService, so a hosted database with Hibernate validation still starts
// before it exists.
@Data
@NoArgsConstructor
@AllArgsConstructor
public class Article {
    private Long id;
    private Long categoryId;
    private String articleName;
}
