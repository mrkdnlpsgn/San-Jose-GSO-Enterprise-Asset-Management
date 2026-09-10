package com.sanjose.inventory.entity;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import jakarta.persistence.*;
import lombok.*;
import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;

@Entity
@Table(name = "assets")
@Data
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class Asset {

    public enum AssetCondition { SERVICEABLE, REPAIRABLE, UNSERVICEABLE }
    public enum LifecycleStatus { REGISTERED, ASSIGNED, TRANSFERRED, UNDER_MAINTENANCE, DISPOSED, ARCHIVED }

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    @Column(name = "asset_id")
    private Long id;

    @Column(name = "property_number", nullable = false, unique = true, length = 50)
    private String propertyNumber;

    @Column(name = "serial_number", length = 100)
    private String serialNumber;

    @Column(nullable = false, length = 255)
    private String description;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "category_id", nullable = false)
    @JsonIgnoreProperties({"description"})
    private Category category;

    @Builder.Default
    @Column(nullable = false)
    private Integer quantity = 1;

    @Column(name = "acquisition_date", nullable = false)
    private LocalDate acquisitionDate;

    @Column(name = "unit_value", nullable = false, precision = 12, scale = 2)
    private BigDecimal unitValue;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "office_id", nullable = false)
    @JsonIgnoreProperties({"headUser", "createdAt"})
    private Office office;

    @Column(name = "accountable_person", length = 150)
    private String accountablePerson;

    @Column(name = "physical_count")
    private Integer physicalCount;

    @Column(nullable = false, length = 150)
    private String location;

    @Enumerated(EnumType.STRING)
    @Column(name = "condition", nullable = false)
    private AssetCondition condition;

    @Enumerated(EnumType.STRING)
    @Column(name = "lifecycle_status", nullable = false)
    private LifecycleStatus lifecycleStatus;

    @Column(name = "qr_code_path", length = 255)
    private String qrCodePath;

    @Column(name = "sha256_hash", length = 64)
    private String sha256Hash;

    @Column(columnDefinition = "TEXT")
    private String remarks;

    // Computed on read from unitValue + acquisitionDate + category.usefulLifeYears
    // (see DepreciationCalculator) — informational only, never persisted, and
    // never used to gate disposal eligibility (that's driven by `condition`).
    @Transient
    private java.math.BigDecimal accumulatedDepreciation;

    @Transient
    private java.math.BigDecimal carryingAmount;

    @Builder.Default
    @Column(name = "is_deleted", nullable = false)
    private Boolean isDeleted = false;

    @Column(name = "deleted_at")
    private LocalDateTime deletedAt;

    @Column(name = "deleted_by")
    private Long deletedBy;

    @Column(name = "delete_reason", columnDefinition = "TEXT")
    private String deleteReason;

    @Column(name = "created_at", nullable = false, updatable = false)
    private LocalDateTime createdAt;

    @Column(name = "updated_at", nullable = false)
    private LocalDateTime updatedAt;

    @PrePersist
    protected void onCreate() {
        createdAt = updatedAt = LocalDateTime.now();
    }

    @PreUpdate
    protected void onUpdate() {
        updatedAt = LocalDateTime.now();
    }
}
