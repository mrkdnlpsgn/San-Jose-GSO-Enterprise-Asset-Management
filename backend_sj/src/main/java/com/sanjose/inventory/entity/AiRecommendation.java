package com.sanjose.inventory.entity;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import jakarta.persistence.*;
import lombok.*;

import java.math.BigDecimal;
import java.time.LocalDateTime;

@Entity
@Table(name = "ai_recommendations")
@Data
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class AiRecommendation {

    public enum Recommendation { MAINTAIN, REPAIR, MONITOR, REVIEW_FOR_DISPOSAL, BUDGET_PRIORITY }

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    @Column(name = "recommendation_id")
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "asset_id", nullable = false, columnDefinition = "INT")
    @JsonIgnoreProperties({"category", "office", "accountablePerson", "remarks", "qrCodePath", "sha256Hash"})
    private Asset asset;

    @Column(name = "asset_age_years", nullable = false, precision = 5, scale = 2)
    private BigDecimal assetAgeYears;

    @Column(name = "total_repair_cost", nullable = false, precision = 12, scale = 2)
    private BigDecimal totalRepairCost;

    @Column(name = "repair_frequency", nullable = false)
    private Integer repairFrequency;

    @Column(name = "condition_score", nullable = false)
    private Integer conditionScore;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    private Recommendation recommendation;

    @Column(columnDefinition = "TEXT", nullable = false)
    private String rationale;

    @Column(name = "generated_at", nullable = false)
    private LocalDateTime generatedAt;

    @Column(name = "generated_by_system", nullable = false)
    private Boolean generatedBySystem;

    @PrePersist
    protected void onCreate() {
        if (generatedAt == null) generatedAt = LocalDateTime.now();
        if (generatedBySystem == null) generatedBySystem = true;
    }
}
