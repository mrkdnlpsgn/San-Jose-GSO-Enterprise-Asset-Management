package com.sanjose.inventory.entity;

import jakarta.persistence.*;
import lombok.*;
import java.time.LocalDate;
import java.time.LocalDateTime;

@Entity
@Table(name = "deleted_disposal")
@Data
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class DeletedDisposal {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    @Column(name = "deleted_disposal_id")
    private Long id;

    @Column(name = "disposal_id", nullable = false)
    private Long disposalId;

    @Column(name = "asset_id", nullable = false)
    private Long assetId;

    @Column(name = "property_number", nullable = false, length = 50)
    private String propertyNumber;

    @Column(name = "par_number", length = 50)
    private String parNumber;

    @Column(name = "asset_description", nullable = false, length = 255)
    private String assetDescription;

    @Column(nullable = false, columnDefinition = "TEXT")
    private String reason;

    @Column(name = "inspection_findings", nullable = false, columnDefinition = "TEXT")
    private String inspectionFindings;

    @Column(name = "recommended_method", nullable = false, length = 20)
    private String recommendedMethod;

    @Column(name = "disposal_status", nullable = false, length = 20)
    private String disposalStatus;

    @Column(name = "inspection_date", nullable = false)
    private LocalDate inspectionDate;

    @Column(name = "approved_by_user_id")
    private Long approvedByUserId;

    @Column(name = "approved_by_name", length = 100)
    private String approvedByName;

    @Column(name = "recorded_by_user_id", nullable = false)
    private Long recordedByUserId;

    @Column(name = "recorded_by_name", nullable = false, length = 100)
    private String recordedByName;

    @Column(name = "original_created_at", nullable = false)
    private LocalDateTime originalCreatedAt;

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
