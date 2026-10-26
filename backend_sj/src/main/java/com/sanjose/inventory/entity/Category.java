package com.sanjose.inventory.entity;

import jakarta.persistence.*;
import lombok.*;

@Entity
@Table(name = "categories")
@Data
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class Category {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    @Column(name = "category_id", columnDefinition = "INT")
    private Long id;

    @Column(name = "category_name", nullable = false, unique = true, length = 100)
    private String categoryName;

    @Column(columnDefinition = "TEXT")
    private String description;

    @Column(name = "useful_life_years")
    private Integer usefulLifeYears;

    // The code in this category's place in property numbers (see PropertyNumberService).
    // Not mapped: the column is added at startup, so Hibernate validation doesn't depend on it.
    @Transient
    private String propertyCode;
}
