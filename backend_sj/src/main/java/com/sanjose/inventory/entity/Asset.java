package com.sanjose.inventory.entity;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import jakarta.persistence.*;
import lombok.*;
import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;

@Entity
@Table(name = "assets", indexes = @Index(name = "idx_assets_group", columnList = "group_id"))
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

    // Property Acknowledgment Receipt number — distinct from propertyNumber (the
    // COA-assigned one). Format is YYYY-MM:SERIAL: the acquisition year-month plus
    // a serial the user types in by hand, e.g. "2026-07:H78JD80". Unique, like
    // propertyNumber — together they tell identical devices apart. Nullable at the
    // column level only so rows that predate this field survive the schema
    // update; AssetService requires it on every create/update.
    @Column(name = "par_number", unique = true, length = 50)
    private String parNumber;

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

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "personnel_id")
    @JsonIgnoreProperties({"office"})
    private Personnel accountablePerson;

    // The person who currently has physical possession/use of the asset — can
    // differ from accountablePerson, who is formally responsible for it on paper.
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "current_user_personnel_id")
    @JsonIgnoreProperties({"office"})
    private Personnel currentUser;

    // Devices added together (Qty > 1 on the Add form, or an old multi-quantity record
    // that was split up) share this id so the UI can group same-model assets under one
    // expandable row. Each member is still a complete, independent asset. Null = standalone.
    @Column(name = "group_id", length = 36)
    private String groupId;

    // Read-only roll-up for a grouped asset (0/absent when standalone): how many devices are in
    // its group, and their combined value — so a list showing only some of them can still
    // display the true totals.
    @Transient
    private Integer groupSize;

    @Transient
    private java.math.BigDecimal groupTotalValue;

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

    // Free-form — the fields that matter vary entirely by device type (CPU/RAM/storage
    // for a computer, engine/plate no. for a vehicle, BTU/voltage for an aircon, etc.),
    // matching how these are recorded on the paper Property Acknowledgment Receipt.
    @Column(columnDefinition = "TEXT")
    private String specifications;
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
