package com.sanjose.inventory.entity;

import jakarta.persistence.*;
import lombok.*;
import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;

@Entity
@Table(name = "deleted_assets")
@Data
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class DeletedAsset {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    @Column(name = "deleted_asset_id")
    private Long id;

    @Column(name = "asset_id", nullable = false)
    private Long assetId;

    @Column(name = "property_number", nullable = false, length = 50)
    private String propertyNumber;

    @Column(name = "par_number", length = 50)
    private String parNumber;

    @Column(nullable = false, length = 255)
    private String description;

    @Column(name = "category_id", nullable = false)
    private Long categoryId;

    @Column(name = "category_name", nullable = false, length = 100)
    private String categoryName;

    @Column(nullable = false)
    private Integer quantity;

    @Column(name = "acquisition_date", nullable = false)
    private LocalDate acquisitionDate;

    @Column(name = "unit_value", nullable = false, precision = 12, scale = 2)
    private BigDecimal unitValue;

    @Column(name = "office_id", nullable = false)
    private Long officeId;

    @Column(name = "office_name", nullable = false, length = 100)
    private String officeName;

    @Column(name = "accountable_person_id")
    private Long accountablePersonId;

    @Column(name = "accountable_person_name", length = 150)
    private String accountablePersonName;

    @Column(name = "current_user_personnel_id")
    private Long currentUserPersonnelId;

    @Column(name = "current_user_name", length = 150)
    private String currentUserName;

    @Column(nullable = false, length = 150)
    private String location;

    @Column(name = "asset_condition", nullable = false, length = 20)
    private String condition;

    @Column(name = "lifecycle_status", nullable = false, length = 30)
    private String lifecycleStatus;

    @Column(name = "qr_code_path", length = 255)
    private String qrCodePath;

    @Column(name = "sha256_hash", length = 64)
    private String sha256Hash;

    @Column(columnDefinition = "TEXT")
    private String remarks;

    @Column(columnDefinition = "TEXT")
    private String specifications;

    @Column(name = "original_created_at", nullable = false)
    private LocalDateTime originalCreatedAt;

    @Column(name = "original_updated_at", nullable = false)
    private LocalDateTime originalUpdatedAt;

    @Column(name = "deleted_by_user_id", nullable = false)
    private Long deletedByUserId;

    @Column(name = "deleted_by_username", nullable = false, length = 50)
    private String deletedByUsername;

    @Column(name = "delete_reason", columnDefinition = "TEXT")
    private String deleteReason;

    @Column(name = "deleted_at", nullable = false)
    private LocalDateTime deletedAt;

    @PrePersist
    protected void onCreate() {
        if (deletedAt == null) deletedAt = LocalDateTime.now();
    }
}
